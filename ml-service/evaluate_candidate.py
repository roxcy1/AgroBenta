"""Read-only comparison of a candidate against the registered models.

This script never trains, registers, activates, or updates a model. It
reconstructs the frozen split for the requested version, evaluates every
compatible model on the same test records, and writes a new timestamped
comparison report.
"""

from __future__ import annotations

import argparse
import json
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import numpy as np
from catboost import CatBoostRegressor

from features import FEATURE_COLUMNS, TARGET_COLUMN
from model_registry import MODELS_DIR, load_verified_model
from train import (
    REPORTS_DIR,
    load_and_validate_dataset,
    median_price_per_kg_baseline,
    sha256_file,
)
from train_candidate import (
    DEFAULT_DATASET,
    MODEL_VERSION,
    SEED,
    TEST_FRACTION,
    VALIDATION_FRACTION,
    VALIDATION_SEED,
    _evaluate,
    _metadata_ood_count,
    _safe,
    _safety_counts,
    split_frames,
)


def _load_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def _latest_candidate(version: str) -> Path:
    candidates = sorted(
        MODELS_DIR.glob(f"candidate_catboost_{version}_*.cbm"),
        key=lambda path: (path.stat().st_mtime, path.name),
        reverse=True,
    )
    if not candidates:
        raise FileNotFoundError(
            f"No candidate_catboost_{version}_*.cbm model found. "
            "Run train_candidate.py first."
        )
    return candidates[0]


def _latest_split_manifest(version: str) -> Path:
    manifests = sorted(
        REPORTS_DIR.glob(f"{version}_split_manifest_*.json"),
        key=lambda path: (path.stat().st_mtime, path.name),
        reverse=True,
    )
    if not manifests:
        raise FileNotFoundError(
            f"No {version}_split_manifest_*.json found. "
            "Train the candidate first."
        )
    return manifests[0]


def _load_candidate(path: Path) -> tuple[CatBoostRegressor, dict[str, Any], dict[str, Any]]:
    if not path.is_file():
        raise FileNotFoundError(f"Candidate model not found: {path}")
    metadata_path = path.with_suffix(".metadata.json")
    safety_path = path.with_suffix(".safety.json")
    if not metadata_path.is_file() or not safety_path.is_file():
        raise FileNotFoundError(
            f"Candidate sidecars are missing for {path.name}."
        )

    metadata = _load_json(metadata_path)
    safety = _load_json(safety_path)
    if metadata.get("model_file") != path.name:
        raise ValueError("Candidate metadata model_file does not match the model.")
    if safety.get("model_file") != path.name:
        raise ValueError("Candidate safety profile model_file does not match the model.")
    if metadata.get("dataset_provenance") != "synthetic":
        raise ValueError("Candidate metadata is not marked synthetic.")

    model = CatBoostRegressor()
    model.load_model(str(path))
    return model, metadata, safety


def _registered_models() -> list[dict[str, Any]]:
    manifest = _load_json(MODELS_DIR / "active_model.json")
    entries = [manifest["active"], *manifest.get("candidates", [])]
    loaded: list[dict[str, Any]] = []
    for registered in entries:
        model, path, entry, metadata, safety = load_verified_model(
            MODELS_DIR / registered["model_file"]
        )
        loaded.append(
            {
                "entry": entry,
                "path": path,
                "model": model,
                "metadata": metadata,
                "safety": safety,
            }
        )
    return loaded


def _evaluate_model(
    test_frame,
    model: CatBoostRegressor,
    metadata: dict[str, Any],
    safety: dict[str, Any],
) -> dict[str, Any]:
    predictions = np.asarray(
        model.predict(test_frame.loc[:, list(FEATURE_COLUMNS)]),
        dtype=float,
    )
    return {
        **_evaluate(test_frame, predictions),
        "safety": _safety_counts(test_frame, safety),
        "metadata_ood_rows": _metadata_ood_count(test_frame, metadata),
    }


def _comparison(candidate: dict[str, Any], other: dict[str, Any]) -> dict[str, float]:
    candidate_overall = candidate["overall"]
    other_overall = other["overall"]
    return {
        "mae_delta": round(candidate_overall["mae"] - other_overall["mae"], 4),
        "rmse_delta": round(candidate_overall["rmse"] - other_overall["rmse"], 4),
        "mape_delta_percent": round(
            candidate_overall["mape_percent"] - other_overall["mape_percent"], 4
        ),
        "r2_delta": round(candidate_overall["r2"] - other_overall["r2"], 4),
    }


def evaluate_candidate(
    *,
    model_path: Path,
    dataset_path: Path,
    split_manifest_path: Path,
    report_path: Path,
    version: str = MODEL_VERSION,
) -> tuple[Path, dict[str, Any]]:
    frame, dataset_summary = load_and_validate_dataset(dataset_path)
    split_manifest = _load_json(split_manifest_path)
    if split_manifest.get("dataset_sha256") not in (None, dataset_summary["sha256"]):
        raise ValueError(
            "Dataset SHA-256 does not match the frozen split manifest."
        )

    train_frame, validation_frame, test_frame, split = split_frames(
        frame,
        seed=int(split_manifest.get("seed", SEED)),
        validation_seed=int(split_manifest.get("validation_seed", VALIDATION_SEED)),
        test_fraction=float(
            split_manifest.get("test_fraction", TEST_FRACTION)
        ),
        validation_fraction=float(
            split_manifest.get(
                "validation_fraction_of_pool", VALIDATION_FRACTION
            )
        ),
    )
    if split_manifest.get("rows", {}).get("test") not in (None, len(test_frame)):
        raise ValueError("Test row count does not match the frozen split manifest.")

    candidate_model, candidate_metadata, candidate_safety = _load_candidate(
        model_path
    )
    candidate = {
        "version": version,
        "file": model_path.name,
        "sha256": sha256_file(model_path),
        **_evaluate_model(
            test_frame,
            candidate_model,
            candidate_metadata,
            candidate_safety,
        ),
    }

    registered = _registered_models()
    models: dict[str, Any] = {}
    comparisons: dict[str, Any] = {}
    for item in registered:
        if item["path"].name == model_path.name:
            continue
        entry = item["entry"]
        model_result = {
            "version": entry["model_version"],
            "file": item["path"].name,
            "sha256": entry["sha256"],
            "provenance": entry.get("provenance"),
            **_evaluate_model(
                test_frame,
                item["model"],
                item["metadata"],
                item["safety"],
            ),
        }
        models[entry["model_version"]] = model_result
        comparisons[entry["model_version"]] = _comparison(
            candidate, model_result
        )

    baseline_predictions, baseline_rates, baseline_global_rate = (
        median_price_per_kg_baseline(train_frame, test_frame)
    )
    baseline = {
        **_evaluate(test_frame, baseline_predictions),
        "training_category_rates_php_per_kg": {
            category: round(rate, 4)
            for category, rate in baseline_rates.items()
        },
        "training_global_rate_php_per_kg": round(baseline_global_rate, 4),
    }
    comparisons["baseline_median_price_per_kg"] = _comparison(
        candidate, baseline
    )

    report: dict[str, Any] = {
        "dataset": {
            "filename": dataset_summary["filename"],
            "sha256": dataset_summary["sha256"],
            "rows_after_deduplication": dataset_summary[
                "rows_after_exact_duplicate_removal"
            ],
            "provenance": "synthetic",
        },
        "split": {
            **split,
            "validation_rows_used_for_reporting_only": int(len(validation_frame)),
        },
        "candidate": candidate,
        "registered_models": models,
        "baseline": baseline,
        "comparison_vs_candidate": comparisons,
        "warning": (
            "Synthetic data only. This comparison does not establish real "
            "Trinidad/Bohol market accuracy."
        ),
        "notes": [
            f"All models are evaluated on the same {version} test rows.",
            "Raw prediction metrics include rows that each model's safety "
            "profile would warn about or withhold; safety status counts are "
            "reported separately.",
            "Older models were trained on a different synthetic distribution; "
            "their metrics are not comparable to their own historical reports.",
        ],
    }

    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text(
        json.dumps(_safe(report), indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )
    return report_path, report


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Evaluate a CatBoost candidate against registered models."
    )
    parser.add_argument("--model", type=Path, default=None)
    parser.add_argument("--version", default=MODEL_VERSION)
    parser.add_argument("--dataset", type=Path, default=DEFAULT_DATASET)
    parser.add_argument(
        "--split-manifest",
        type=Path,
        default=None,
        help="Frozen split manifest. Defaults to the newest for --version.",
    )
    parser.add_argument(
        "--report",
        type=Path,
        default=None,
        help="Report path. Defaults to a new timestamped comparison file.",
    )
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
    try:
        model_path = args.model or _latest_candidate(args.version)
        split_manifest = args.split_manifest or _latest_split_manifest(
            args.version
        )
        report_path = args.report or (
            REPORTS_DIR / f"candidate_{args.version}_comparison_{stamp}.json"
        )
        report_path, report = evaluate_candidate(
            model_path=model_path,
            dataset_path=args.dataset,
            split_manifest_path=split_manifest,
            report_path=report_path,
            version=args.version,
        )
    except (FileNotFoundError, ValueError, KeyError) as exc:
        print(f"Candidate evaluation failed: {exc}")
        return 1

    candidate = report["candidate"]["overall"]
    baseline = report["baseline"]["overall"]
    print(f"Candidate: {model_path}")
    print(f"Report:    {report_path}")
    print(
        "Candidate MAE/RMSE/MAPE/R2: "
        f"{candidate['mae']:.2f} / {candidate['rmse']:.2f} / "
        f"{candidate['mape_percent']:.2f}% / {candidate['r2']:.4f}"
    )
    print(
        "Baseline  MAE/RMSE/MAPE/R2: "
        f"{baseline['mae']:.2f} / {baseline['rmse']:.2f} / "
        f"{baseline['mape_percent']:.2f}% / {baseline['r2']:.4f}"
    )
    for version, comparison in report["comparison_vs_candidate"].items():
        print(
            f"vs {version}: MAE {comparison['mae_delta']:+.2f}, "
            f"MAPE {comparison['mape_delta_percent']:+.2f} pp, "
            f"R2 {comparison['r2_delta']:+.4f}"
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
