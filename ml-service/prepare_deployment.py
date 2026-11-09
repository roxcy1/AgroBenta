"""Build additive safety profiles and the active-model manifest.

This does not train, promote, overwrite, or delete any model or report. It reads
the existing v1/v2/v3 artifacts, derives per-category/breed safety envelopes
from their training rows, and writes:

    models/<model>.safety.json       (additive, one per model)
    models/active_model.json         (active v1; v2/v3 remain candidates)

Run once after the models are present.
"""

from __future__ import annotations

import json
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from model_registry import (
    MODELS_DIR,
    ModelIntegrityError,
    load_verified_model,
    sha256_file,
)
from train import assign_split, load_and_validate_dataset
from train_young_chicken import split_young_chickens
from validation import build_safety_profile, safety_profile_path, save_safety_profile

BASE_DIR = Path(__file__).resolve().parent
ORIGINAL_DATASET = BASE_DIR / "data" / "synthetic_livestock_sales.csv"
EXPANDED_DATASET = BASE_DIR / "data" / "synthetic_livestock_sales_v2.csv"
REPORTS_DIR = BASE_DIR / "reports"
MANIFEST_PATH = MODELS_DIR / "active_model.json"


def _write_if_missing(path: Path, content: dict[str, Any]) -> bool:
    if path.exists():
        return False
    path.write_text(
        json.dumps(content, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )
    return True


def main() -> int:
    try:
        original, _ = load_and_validate_dataset(ORIGINAL_DATASET)
        original_train, _ = assign_split(original, 0.2, 42)
        expanded, _ = load_and_validate_dataset(EXPANDED_DATASET)
        young = expanded[
            (expanded["livestock_type"] == "chicken")
            & (expanded["age_months"] < 1.0)
        ].reset_index(drop=True)
        young_train, _, _ = split_young_chickens(young)
        import pandas as pd

        v2_train = pd.concat(
            [original_train, young_train], ignore_index=True
        )

        v1_report = json.loads(
            (REPORTS_DIR / "metrics.json").read_text(encoding="utf-8")
        )
        v2_report = json.loads(
            (REPORTS_DIR / "young_chicken_training_v2.json").read_text(
                encoding="utf-8"
            )
        )
        v3_report = json.loads(
            (REPORTS_DIR / "targeted_improvement_v3_final.json").read_text(
                encoding="utf-8"
            )
        )
    except (FileNotFoundError, RuntimeError, ValueError) as exc:
        print(f"Deployment preparation failed: {exc}", file=sys.stderr)
        return 1

    entries = [
        {
            "model_version": v1_report["model"]["version"],
            "model_file": v1_report["model"]["file"],
            "metadata_file": Path(v1_report["model"]["file"])
            .with_suffix(".metadata.json")
            .name,
            "safety_profile_file": Path(v1_report["model"]["file"])
            .with_suffix(".safety.json")
            .name,
            "sha256": v1_report["model"]["sha256"],
            "provenance": v1_report["dataset"]["provenance"],
            "status": "active",
            "training_rows": int(len(original_train)),
        },
        {
            "model_version": v2_report["candidate"]["version"],
            "model_file": v2_report["candidate"]["file"],
            "metadata_file": Path(v2_report["candidate"]["file"])
            .with_suffix(".metadata.json")
            .name,
            "safety_profile_file": Path(v2_report["candidate"]["file"])
            .with_suffix(".safety.json")
            .name,
            "sha256": v2_report["candidate"]["sha256"],
            "provenance": v2_report["dataset"]["expanded"]["provenance"]
            if "provenance" in v2_report["dataset"]["expanded"]
            else "synthetic",
            "status": "candidate",
            "training_rows": int(v2_report["candidate"]["training_rows"]),
        },
        {
            "model_version": v3_report["saved_model"]["version"],
            "model_file": v3_report["saved_model"]["file"],
            "metadata_file": Path(v3_report["saved_model"]["file"])
            .with_suffix(".metadata.json")
            .name,
            "safety_profile_file": Path(v3_report["saved_model"]["file"])
            .with_suffix(".safety.json")
            .name,
            "sha256": v3_report["saved_model"]["sha256"],
            "provenance": "synthetic",
            "status": "candidate",
            "training_rows": int(v3_report["dataset"]["v2_training_rows"]),
        },
    ]

    safety_frames = {
        v1_report["model"]["file"]: original_train,
        v2_report["candidate"]["file"]: v2_train,
        v3_report["saved_model"]["file"]: v2_train,
    }

    for entry in entries:
        model_path = MODELS_DIR / entry["model_file"]
        if not model_path.is_file():
            print(f"Missing model: {model_path}", file=sys.stderr)
            return 1
        actual_hash = sha256_file(model_path)
        if actual_hash != entry["sha256"]:
            print(
                f"Hash mismatch for {model_path.name}: report {entry['sha256']}, "
                f"actual {actual_hash}",
                file=sys.stderr,
            )
            return 1

        safety_path = safety_profile_path(model_path)
        profile = build_safety_profile(
            safety_frames[entry["model_file"]],
            model_file=model_path.name,
            provenance=entry["provenance"],
        )
        if _write_if_missing(safety_path, profile):
            print(f"Wrote safety profile: {safety_path.name}")
        else:
            existing = json.loads(safety_path.read_text(encoding="utf-8"))
            if existing != profile:
                print(
                    f"Existing safety profile differs; preserving {safety_path.name}",
                    file=sys.stderr,
                )

    manifest = {
        "schema_version": 1,
        "updated_at_utc": datetime.now(timezone.utc).strftime(
            "%Y-%m-%dT%H:%M:%SZ"
        ),
        "active": entries[0],
        "rollback": {
            "available": False,
            "target_model_file": None,
            "reason": (
                "v1 is the initial active model. v2 and v3 are candidates and "
                "must not be promoted automatically."
            ),
        },
        "candidates": entries[1:],
        "safety_policy": {
            "hard_envelope": "observed category age/weight minimum and maximum",
            "typical_range": "category and breed 1st-99th percentiles",
            "joint_check": "observed weight minimum/maximum within each category age bin",
            "missing_profile": "withhold prediction",
            "note": (
                "Data-derived prototype rules only; not authoritative biological "
                "limits or market evidence."
            ),
        },
    }

    if MANIFEST_PATH.exists():
        print(f"Preserving existing manifest: {MANIFEST_PATH}")
    else:
        MANIFEST_PATH.write_text(
            json.dumps(manifest, indent=2, ensure_ascii=False) + "\n",
            encoding="utf-8",
        )
        print(f"Wrote manifest: {MANIFEST_PATH}")

    # Validate the active model through the same path deployment will use.
    try:
        _, path, entry, _, safety = load_verified_model()
    except (ModelIntegrityError, RuntimeError) as exc:
        print(f"Active model validation failed: {exc}", file=sys.stderr)
        return 1

    print(f"Active model: {entry['model_version']} ({path.name})")
    print(f"Safety categories: {', '.join(sorted(safety['categories']))}")
    print("Candidates preserved: v2-young-chicken, v3-targeted")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
