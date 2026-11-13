"""Active-model manifest and integrity checks for deployment.

The manifest is explicit: the active model is never chosen by filename
modification time. ``MODEL_PATH`` or the ``--model`` argument may select an
entry already listed in the manifest, but unregistered models are rejected by
the verified loading path.
"""

from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
from typing import Any, Mapping

from catboost import CatBoostRegressor

from validation import load_safety_profile, load_training_profile

BASE_DIR = Path(__file__).resolve().parent
MODELS_DIR = BASE_DIR / "models"
MANIFEST_NAME = "active_model.json"


class ModelConfigurationError(RuntimeError):
    """The configured or active model cannot be selected safely."""


class ModelIntegrityError(RuntimeError):
    """A selected model, its metadata, or its safety profile is invalid."""


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def manifest_path(models_dir: Path | None = None) -> Path:
    directory = MODELS_DIR if models_dir is None else Path(models_dir)
    return directory / MANIFEST_NAME


def load_manifest(models_dir: Path | None = None) -> dict[str, Any]:
    path = manifest_path(models_dir)
    if not path.is_file():
        raise ModelConfigurationError(
            f"Active-model manifest not found: {path}. "
            "Run `python prepare_deployment.py` or set MODEL_PATH explicitly."
        )
    try:
        manifest = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise ModelConfigurationError(
            f"Active-model manifest is not valid JSON: {path}"
        ) from exc

    if not isinstance(manifest, Mapping) or "active" not in manifest:
        raise ModelConfigurationError(
            f"Active-model manifest is missing an active model: {path}"
        )
    return dict(manifest)


def _all_entries(manifest: Mapping[str, Any]) -> list[dict[str, Any]]:
    entries: list[dict[str, Any]] = []
    active = manifest.get("active")
    if isinstance(active, Mapping):
        entries.append(dict(active))
    for key in ("candidates", "available"):
        values = manifest.get(key, [])
        if isinstance(values, list):
            entries.extend(
                dict(entry) for entry in values if isinstance(entry, Mapping)
            )
    return entries


def find_entry(manifest: Mapping[str, Any], filename: str) -> dict[str, Any] | None:
    for entry in _all_entries(manifest):
        if entry.get("model_file") == filename:
            return entry
    return None


def resolve_entry(
    model_path: Path | None = None,
    models_dir: Path | None = None,
    environ: Mapping[str, str] | None = None,
) -> tuple[dict[str, Any], Path | None]:
    """Resolve the active or explicitly configured registered model entry."""
    manifest = load_manifest(models_dir)
    environment = os.environ if environ is None else environ
    configured = model_path or environment.get("MODEL_PATH")

    if configured:
        path = Path(configured)
        entry = find_entry(manifest, path.name)
        if entry is None:
            raise ModelConfigurationError(
                f"Model {path.name!r} is not registered in {manifest_path(models_dir)}. "
                "Register it before using it in a deployment."
            )
        return entry, path

    active = manifest.get("active")
    if not isinstance(active, Mapping):
        raise ModelConfigurationError("Manifest has no active model entry.")
    return dict(active), None


def _entry_path(entry: Mapping[str, Any], models_dir: Path) -> Path:
    model_file = entry.get("model_file")
    if not isinstance(model_file, str) or not model_file:
        raise ModelConfigurationError("Manifest entry has no model_file.")
    return models_dir / model_file


def _verify_paths(
    entry: Mapping[str, Any],
    model_path: Path,
    models_dir: Path,
) -> tuple[dict[str, Any], dict[str, Any]]:
    expected_sha = entry.get("sha256")
    if not isinstance(expected_sha, str) or len(expected_sha) != 64:
        raise ModelIntegrityError(
            f"Manifest entry for {model_path.name} has no valid SHA-256."
        )
    if not model_path.is_file():
        raise ModelConfigurationError(f"Model file not found: {model_path}")
    actual_sha = sha256_file(model_path)
    if actual_sha != expected_sha:
        raise ModelIntegrityError(
            f"Model SHA-256 mismatch for {model_path.name}: expected "
            f"{expected_sha}, got {actual_sha}."
        )

    metadata = load_training_profile(model_path)
    if not metadata:
        raise ModelIntegrityError(
            f"Model metadata sidecar is missing or unreadable: "
            f"{model_path.with_suffix('.metadata.json')}"
        )
    if metadata.get("model_file") != model_path.name:
        raise ModelIntegrityError(
            "Model metadata model_file does not match the selected model."
        )
    if metadata.get("dataset_provenance") != entry.get("provenance"):
        raise ModelIntegrityError(
            "Model metadata provenance does not match the manifest."
        )
    if not metadata.get("feature_ranges"):
        raise ModelIntegrityError("Model metadata has no feature ranges.")

    safety = load_safety_profile(model_path)
    if not safety:
        raise ModelIntegrityError(
            f"Model safety profile is missing or unreadable: "
            f"{model_path.with_suffix('.safety.json')}"
        )
    if safety.get("model_file") != model_path.name:
        raise ModelIntegrityError(
            "Model safety profile model_file does not match the selected model."
        )
    if not safety.get("categories"):
        raise ModelIntegrityError("Model safety profile has no category coverage.")

    expected_metadata = entry.get("metadata_file")
    if expected_metadata and expected_metadata != model_path.with_suffix(
        ".metadata.json"
    ).name:
        raise ModelIntegrityError("Manifest metadata_file does not match the model.")
    expected_safety = entry.get("safety_profile_file")
    if expected_safety and expected_safety != model_path.with_suffix(
        ".safety.json"
    ).name:
        raise ModelIntegrityError(
            "Manifest safety_profile_file does not match the model."
        )

    return dict(metadata), dict(safety)


def load_verified_model(
    model_path: Path | None = None,
    models_dir: Path | None = None,
    environ: Mapping[str, str] | None = None,
    *,
    allow_unregistered: bool = False,
) -> tuple[CatBoostRegressor, Path, dict[str, Any], dict[str, Any], dict[str, Any]]:
    """Resolve, verify and load one model.

    Returns ``(model, path, entry, metadata, safety)``. ``allow_unregistered``
    exists only for isolated tests and local experimentation; deployment callers
    should leave it false.
    """
    directory = MODELS_DIR if models_dir is None else Path(models_dir)
    if model_path is not None and not Path(model_path).is_file():
        raise FileNotFoundError(f"Model not found: {model_path}")

    try:
        entry, explicit_path = resolve_entry(model_path, directory, environ)
    except (ModelConfigurationError, FileNotFoundError):
        if not allow_unregistered or model_path is None:
            raise
        path = Path(model_path)
        entry = {
            "model_version": "unregistered",
            "model_file": path.name,
            "sha256": sha256_file(path) if path.is_file() else "",
            "provenance": "unknown",
        }
        explicit_path = path

    path = explicit_path if explicit_path is not None else _entry_path(entry, directory)
    if not path.is_file():
        raise ModelConfigurationError(f"Model file not found: {path}")

    if allow_unregistered and entry.get("model_version") == "unregistered":
        metadata = load_training_profile(path) or {}
        safety = load_safety_profile(path) or {}
    else:
        metadata, safety = _verify_paths(entry, path, directory)

    model = CatBoostRegressor()
    model.load_model(str(path))
    return model, path, dict(entry), metadata, safety
