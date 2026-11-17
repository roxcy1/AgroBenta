"""Build the revised (schema 2) safety profile for a trained candidate.

The CatBoost model is never touched. The new profile is written beside the
original one under a versioned filename so the previous artifact survives::

    models/<model>.safety.json     # original, untouched
    models/<model>.safety_v2.json  # revised, schema 2

Run from the ml-service directory::

    python build_v5_safety_profile.py --version v5
"""

from __future__ import annotations

import argparse
import json
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from train import MODELS_DIR, REPORTS_DIR, load_and_validate_dataset, sha256_file
from train_candidate import MODEL_VERSION, split_frames
from validation import (
    APPROVED_WEIGHT_LIMITS,
    GROWTH_WINDOWS,
    assess_safety,
    build_safety_profile,
)

BASE_DIR = Path(__file__).resolve().parent
DATASET_PATH = BASE_DIR / "data" / "livestock_sales_v5_synthetic.csv"
PROFILE_SUFFIX = ".safety_v2.json"
# The biological windows are stricter than the synthetic generator in a few
# young-swine cells. A tiny withheld fraction is expected and reported; a large
# one means the profile is wrong.
MAX_WITHHELD_FRACTION = 0.02


def _latest_model(version: str) -> Path:
    models = sorted(
        MODELS_DIR.glob(f"candidate_catboost_{version}_*.cbm"),
        key=lambda path: (path.stat().st_mtime, path.name),
        reverse=True,
    )
    if not models:
        raise FileNotFoundError(
            f"No candidate_catboost_{version}_*.cbm model found."
        )
    return models[0]


def _latest_split_manifest(version: str) -> Path:
    manifests = sorted(
        REPORTS_DIR.glob(f"{version}_split_manifest_*.json"),
        key=lambda path: (path.stat().st_mtime, path.name),
        reverse=True,
    )
    if not manifests:
        raise FileNotFoundError(
            f"No {version}_split_manifest_*.json found."
        )
    return manifests[0]


def build(
    *,
    version: str = MODEL_VERSION,
    dataset_path: Path = DATASET_PATH,
    model_path: Path | None = None,
    split_manifest_path: Path | None = None,
) -> tuple[Path, dict[str, Any]]:
    model_path = model_path or _latest_model(version)
    split_manifest_path = split_manifest_path or _latest_split_manifest(version)
    split_manifest = json.loads(
        split_manifest_path.read_text(encoding="utf-8")
    )

    frame, dataset_summary = load_and_validate_dataset(dataset_path)
    if split_manifest.get("dataset_sha256") not in (
        None,
        dataset_summary["sha256"],
    ):
        raise ValueError("Dataset SHA-256 does not match the split manifest.")

    train, _validation, _test, _split = split_frames(
        frame,
        seed=int(split_manifest.get("seed", 42)),
        validation_seed=int(split_manifest.get("validation_seed", 43)),
        test_fraction=float(split_manifest.get("test_fraction", 0.15)),
        validation_fraction=float(
            split_manifest.get("validation_fraction_of_pool", 0.176470588)
        ),
    )

    profile = build_safety_profile(
        train,
        model_file=model_path.name,
        provenance="synthetic",
    )
    profile.update(
        {
            "model_version": version,
            "dataset_label": "synthetic: reviewed source, corrected for v5",
            "dataset_sha256": dataset_summary["sha256"],
            "safety_schema_note": (
                "Schema 2: approved limits are the hard weight boundary, "
                "growth windows withhold implausible age-weight combinations, "
                "and breed warnings are conditioned on age."
            ),
        }
    )

    withheld = []
    for row in train[
        ["livestock_type", "breed", "sex", "age_months", "weight_kg"]
    ].itertuples(index=False, name=None):
        values = {
            "livestock_type": row[0],
            "breed": row[1],
            "sex": row[2],
            "age_months": float(row[3]),
            "weight_kg": float(row[4]),
        }
        assessment = assess_safety(values, profile)
        if assessment.status == "withheld":
            withheld.append(
                {
                    "livestock_type": row[0],
                    "breed": row[1],
                    "age_months": float(row[3]),
                    "weight_kg": float(row[4]),
                    "reason_codes": list(assessment.reason_codes),
                }
            )
    if withheld:
        fraction = len(withheld) / len(train)
        if fraction > MAX_WITHHELD_FRACTION:
            raise ValueError(
                f"The revised profile withholds {len(withheld)} of "
                f"{len(train)} training rows ({fraction:.2%}), above the "
                f"{MAX_WITHHELD_FRACTION:.0%} tolerance; first: {withheld[0]}"
            )

    profile_path = model_path.with_suffix(PROFILE_SUFFIX)
    profile_path.write_text(
        json.dumps(profile, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )

    summary = {
        "generated_at_utc": datetime.now(timezone.utc).strftime(
            "%Y-%m-%dT%H:%M:%SZ"
        ),
        "model_version": version,
        "model_file": model_path.name,
        "model_sha256": sha256_file(model_path),
        "original_safety_profile": model_path.with_suffix(
            ".safety.json"
        ).name,
        "revised_safety_profile": profile_path.name,
        "revised_safety_sha256": sha256_file(profile_path),
        "dataset_sha256": dataset_summary["sha256"],
        "split_manifest": split_manifest_path.name,
        "training_rows": int(len(train)),
        "schema_version": profile["schema_version"],
        "approved_weight_limits": {
            category: list(bounds)
            for category, bounds in APPROVED_WEIGHT_LIMITS.items()
        },
        "growth_window_count": {
            category: len(bands)
            for category, bands in GROWTH_WINDOWS.items()
        },
        "breed_age_bins": {
            category: {
                breed: len(data.get("age_bins", []))
                for breed, data in category_data.get("breeds", {}).items()
            }
            for category, category_data in profile["categories"].items()
        },
        "training_rows_withheld": len(withheld),
        "training_rows_withheld_fraction": round(
            len(withheld) / len(train), 6
        ),
        "withheld_examples": withheld[:5],
        "withheld_note": (
            "Rows withheld by the biological windows are synthetic records the "
            "generator produced outside plausible age-weight ranges. The "
            "dataset is not modified; the safety profile declines to price them."
        ),
    }

    report_path = REPORTS_DIR / (
        f"{version}_safety_profile_"
        f"{datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')}.json"
    )
    report_path.write_text(
        json.dumps(summary, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )
    return profile_path, summary


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Build the revised schema 2 safety profile for a candidate."
    )
    parser.add_argument("--version", default=MODEL_VERSION)
    parser.add_argument("--dataset", type=Path, default=DATASET_PATH)
    parser.add_argument("--model", type=Path, default=None)
    parser.add_argument("--split-manifest", type=Path, default=None)
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    try:
        profile_path, summary = build(
            version=args.version,
            dataset_path=args.dataset,
            model_path=args.model,
            split_manifest_path=args.split_manifest,
        )
    except (FileNotFoundError, ValueError) as exc:
        print(f"Safety profile build failed: {exc}")
        return 1

    print(f"Revised profile: {profile_path}")
    print(f"Model:           {summary['model_file']}")
    print(
        f"Schema {summary['schema_version']} · training rows "
        f"{summary['training_rows']} · withheld {summary['training_rows_withheld']}"
    )
    print("Original profile untouched.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
