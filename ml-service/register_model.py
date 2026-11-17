"""Register a verified candidate, or activate one with a rollback record.

Candidate registration is the default and never changes the active model.
Activation is explicit and records the previous active entry for rollback.
"""

from __future__ import annotations

import argparse
import json
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from model_registry import MODELS_DIR, ModelConfigurationError, sha256_file

MANIFEST_PATH = MODELS_DIR / "active_model.json"


def _load_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def _entry_for(
    model_path: Path,
    *,
    version: str,
    provenance: str,
    status: str,
    safety_profile: Path | None = None,
) -> dict[str, Any]:
    metadata_path = model_path.with_suffix(".metadata.json")
    safety_path = (
        Path(safety_profile)
        if safety_profile is not None
        else model_path.with_suffix(".safety.json")
    )
    if not model_path.is_file():
        raise ModelConfigurationError(f"Model not found: {model_path}")
    if not metadata_path.is_file() or not safety_path.is_file():
        raise ModelConfigurationError(
            "The model metadata and safety-profile sidecars are required."
        )
    if safety_path.parent.resolve() != model_path.parent.resolve():
        raise ModelConfigurationError(
            "The safety profile must sit beside the model file."
        )

    metadata = _load_json(metadata_path)
    safety = _load_json(safety_path)
    if metadata.get("model_file") != model_path.name:
        raise ModelConfigurationError("Metadata model_file does not match the model.")
    if safety.get("model_file") != model_path.name:
        raise ModelConfigurationError("Safety model_file does not match the model.")
    if metadata.get("dataset_provenance") != provenance:
        raise ModelConfigurationError(
            "Metadata provenance does not match the requested provenance."
        )

    return {
        "model_version": version,
        "model_file": model_path.name,
        "metadata_file": metadata_path.name,
        "safety_profile_file": safety_path.name,
        "safety_schema_version": safety.get("schema_version"),
        "sha256": sha256_file(model_path),
        "provenance": provenance,
        "status": status,
        "training_rows": int(metadata.get("training_rows", 0)),
    }


def register_candidate(
    model_path: Path,
    *,
    version: str,
    provenance: str,
    safety_profile: Path | None = None,
) -> dict[str, Any]:
    manifest = _load_json(MANIFEST_PATH)
    entry = _entry_for(
        model_path,
        version=version,
        provenance=provenance,
        status="candidate",
        safety_profile=safety_profile,
    )
    candidates = [
        candidate
        for candidate in manifest.get("candidates", [])
        if candidate.get("model_file") != entry["model_file"]
    ]
    candidates.append(entry)
    manifest["candidates"] = candidates
    manifest["updated_at_utc"] = datetime.now(timezone.utc).strftime(
        "%Y-%m-%dT%H:%M:%SZ"
    )
    _write_manifest(manifest)
    return entry


def activate(
    model_path: Path,
    *,
    version: str,
    provenance: str,
    safety_profile: Path | None = None,
) -> dict[str, Any]:
    manifest = _load_json(MANIFEST_PATH)
    current = manifest.get("active")
    if not isinstance(current, dict):
        raise ModelConfigurationError("Manifest has no active entry to roll back to.")

    entry = _entry_for(
        model_path,
        version=version,
        provenance=provenance,
        status="active",
        safety_profile=safety_profile,
    )
    if current.get("model_file") == entry["model_file"]:
        raise ModelConfigurationError("That model is already active.")

    manifest["active"] = entry
    manifest["rollback"] = {
        "available": True,
        "target_model_file": current.get("model_file"),
        "target_model_version": current.get("model_version"),
        "entry": current,
        "reason": (
            f"Activated {version}; rollback entry preserves the previously "
            "active model."
        ),
    }
    manifest["candidates"] = [
        candidate
        for candidate in manifest.get("candidates", [])
        if candidate.get("model_file") != entry["model_file"]
    ]
    manifest["updated_at_utc"] = datetime.now(timezone.utc).strftime(
        "%Y-%m-%dT%H:%M:%SZ"
    )
    _write_manifest(manifest)
    return entry


def _write_manifest(manifest: dict[str, Any]) -> None:
    temporary = MANIFEST_PATH.with_suffix(".json.tmp")
    temporary.write_text(
        json.dumps(manifest, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )
    temporary.replace(MANIFEST_PATH)


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Register or explicitly activate a verified model."
    )
    parser.add_argument("--model", type=Path, required=True)
    parser.add_argument("--version", required=True)
    parser.add_argument(
        "--provenance",
        choices=("synthetic", "real"),
        default="synthetic",
    )
    parser.add_argument(
        "--safety-profile",
        type=Path,
        default=None,
        help=(
            "Safety profile beside the model. Defaults to the model's "
            ".safety.json; use this to register a revised profile."
        ),
    )
    parser.add_argument(
        "--activate",
        action="store_true",
        help="Explicitly activate the model and record the previous active entry.",
    )
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    try:
        if args.activate:
            entry = activate(
                args.model,
                version=args.version,
                provenance=args.provenance,
                safety_profile=args.safety_profile,
            )
            print(f"Activated {entry['model_version']} ({entry['model_file']}).")
        else:
            entry = register_candidate(
                args.model,
                version=args.version,
                provenance=args.provenance,
                safety_profile=args.safety_profile,
            )
            print(
                f"Registered candidate {entry['model_version']} "
                f"({entry['model_file']}, safety {entry['safety_profile_file']})"
                "; active model unchanged."
            )
    except (ModelConfigurationError, FileNotFoundError, KeyError) as exc:
        print(f"Registration failed: {exc}")
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
