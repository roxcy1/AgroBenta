"""Train a candidate CatBoost model without touching the active v1 artifacts.

Run from the ml-service directory:

    python train_candidate.py --version v5 --provenance synthetic

Defaults target the corrected 4,000-row v5 dataset. The script accepts any
version, dataset and expected shape, so a future candidate does not need a
code change. It writes only candidate-prefixed model files and timestamped,
version-prefixed reports. It does not edit active_model.json,
reports/metrics.json, or any existing model or report.
"""

from __future__ import annotations

import argparse
import json
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import numpy as np
import pandas as pd

from features import (
    CATEGORICAL_FEATURES,
    FEATURE_COLUMNS,
    SUPPORTED_BREEDS,
    TARGET_COLUMN,
    DatasetValidationError,
)
from train import (
    BASE_DIR,
    DEFAULT_DEPTH,
    DEFAULT_ITERATIONS,
    DEFAULT_L2_LEAF_REG,
    DEFAULT_LEARNING_RATE,
    MODELS_DIR,
    REPORTS_DIR,
    assign_split,
    build_model,
    feature_group_keys,
    load_and_validate_dataset,
    median_price_per_kg_baseline,
    per_category_metrics,
    regression_metrics,
    sha256_file,
)
from validation import (
    assess_safety,
    build_safety_profile,
    build_training_profile,
    out_of_distribution_warnings,
    save_safety_profile,
    save_training_profile,
)

DEFAULT_DATASET = BASE_DIR / "data" / "livestock_sales_v5_synthetic.csv"
MODEL_VERSION = "v5"
EXPECTED_ROWS = 4000
EXPECTED_PER_BREED = 200
SEED = 42
TEST_FRACTION = 0.15
VALIDATION_SEED = 43
VALIDATION_FRACTION = 0.15 / (1.0 - TEST_FRACTION)
ITERATIONS = DEFAULT_ITERATIONS
DEPTH = DEFAULT_DEPTH
LEARNING_RATE = DEFAULT_LEARNING_RATE
L2_LEAF_REG = DEFAULT_L2_LEAF_REG
THREAD_COUNT = 4
DATASET_LABEL = "synthetic: reviewed source, corrected for v5"

WARNING = (
    "Synthetic data corrected for v5, for prototype development only. These "
    "metrics do not establish real Trinidad/Bohol market accuracy."
)

# Generic age bands. They apply across categories so the report can separate
# young, growing, mature and older animals without inventing species curves.
AGE_BANDS: tuple[tuple[str, float, float | None], ...] = (
    ("under_6m", 0, 6),
    ("6_to_18m", 6, 18),
    ("18_to_60m", 18, 60),
    ("60m_plus", 60, None),
)


def _expected_audit(
    frame: pd.DataFrame,
    *,
    expected_rows: int = EXPECTED_ROWS,
    expected_per_breed: int = EXPECTED_PER_BREED,
) -> dict[str, Any]:
    """Validate the expected shape and return its count breakdown."""
    errors: list[str] = []
    if len(frame) != expected_rows:
        errors.append(f"expected {expected_rows} rows, got {len(frame)}")

    categories = Counter(str(value) for value in frame["livestock_type"])
    breeds = Counter(
        (str(category), str(breed))
        for category, breed in frame[["livestock_type", "breed"]].itertuples(
            index=False, name=None
        )
    )
    sex_by_breed = Counter(
        (str(category), str(breed), str(sex))
        for category, breed, sex in frame[
            ["livestock_type", "breed", "sex"]
        ].itertuples(index=False, name=None)
    )

    expected_breeds = {
        (category, breed)
        for category, values in SUPPORTED_BREEDS.items()
        for breed in values
    }
    if set(breeds) != expected_breeds:
        errors.append(
            "breed coverage differs from features.py: missing "
            f"{sorted(expected_breeds - set(breeds))}, unexpected "
            f"{sorted(set(breeds) - expected_breeds)}"
        )
    for key, count in sorted(breeds.items()):
        if count != expected_per_breed:
            errors.append(
                f"{key} has {count} rows, expected {expected_per_breed}"
            )
    half = expected_per_breed // 2
    for key in sorted(breeds):
        male, female = sex_by_breed[(key[0], key[1], "male")], sex_by_breed[
            (key[0], key[1], "female")
        ]
        if (male, female) != (half, half):
            errors.append(
                f"{key} sex counts are {male}/{female}, expected {half}/{half}"
            )

    if errors:
        raise DatasetValidationError("; ".join(errors))

    return {
        "rows": int(len(frame)),
        "category_counts": dict(sorted(categories.items())),
        "breed_counts": {
            category: {
                breed: int(breeds[(category, breed)])
                for breed in values
            }
            for category, values in SUPPORTED_BREEDS.items()
        },
        "sex_by_breed": {
            f"{category}/{breed}": {
                "male": int(sex_by_breed[(category, breed, "male")]),
                "female": int(sex_by_breed[(category, breed, "female")]),
            }
            for category, values in SUPPORTED_BREEDS.items()
            for breed in values
        },
    }


def _per_breed_metrics(
    frame: pd.DataFrame,
    predictions: np.ndarray,
) -> dict[str, dict[str, Any]]:
    result: dict[str, dict[str, Any]] = {}
    for (category, breed), group in frame.groupby(
        ["livestock_type", "breed"], sort=True
    ):
        positions = group.index.to_numpy()
        result[f"{category}/{breed}"] = {
            "category": str(category),
            "breed": str(breed),
            "n": int(len(group)),
            **regression_metrics(
                group[TARGET_COLUMN].to_numpy(dtype=float),
                predictions[positions],
            ),
        }
    return result


def _per_age_band_metrics(
    frame: pd.DataFrame,
    predictions: np.ndarray,
) -> dict[str, dict[str, Any]]:
    """Split errors by young, growing, mature and older animals."""
    result: dict[str, dict[str, Any]] = {}
    ages = frame["age_months"]
    for label, low, high in AGE_BANDS:
        mask = ages >= low
        if high is not None:
            mask &= ages < high
        subset = frame[mask]
        if subset.empty:
            continue
        positions = subset.index.to_numpy()
        result[label] = {
            "n": int(len(subset)),
            "age_months": [low, high],
            **regression_metrics(
                subset[TARGET_COLUMN].to_numpy(dtype=float),
                predictions[positions],
            ),
        }
    return result


def _evaluate(
    frame: pd.DataFrame,
    predictions: np.ndarray,
) -> dict[str, Any]:
    return {
        "rows": int(len(frame)),
        "overall": regression_metrics(
            frame[TARGET_COLUMN].to_numpy(dtype=float), predictions
        ),
        "per_category": per_category_metrics(frame, predictions),
        "per_breed": _per_breed_metrics(frame, predictions),
        "per_age_band": _per_age_band_metrics(frame, predictions),
    }


def _safety_counts(
    frame: pd.DataFrame,
    safety_profile: dict[str, Any],
) -> dict[str, Any]:
    counts: Counter[str] = Counter()
    reason_counts: Counter[str] = Counter()
    for row in frame[
        ["livestock_type", "breed", "sex", "age_months", "weight_kg"]
    ].itertuples(index=False, name=None):
        values = {
            "livestock_type": row[0],
            "breed": row[1],
            "sex": row[2],
            "age_months": float(row[3]),
            "weight_kg": float(row[4]),
        }
        assessment = assess_safety(values, safety_profile)
        counts[assessment.status] += 1
        reason_counts.update(assessment.reason_codes)
    return {
        "rows": int(len(frame)),
        "status_counts": {
            status: int(counts.get(status, 0))
            for status in ("ok", "warning", "withheld")
        },
        "reason_code_counts": dict(sorted(reason_counts.items())),
    }


def _metadata_ood_count(
    frame: pd.DataFrame,
    metadata: dict[str, Any],
) -> int:
    count = 0
    for row in frame[
        ["livestock_type", "breed", "sex", "age_months", "weight_kg"]
    ].itertuples(index=False, name=None):
        values = {
            "livestock_type": row[0],
            "breed": row[1],
            "sex": row[2],
            "age_months": float(row[3]),
            "weight_kg": float(row[4]),
        }
        if out_of_distribution_warnings(values, metadata):
            count += 1
    return count


def _safe(value: Any) -> Any:
    if isinstance(value, dict):
        return {key: _safe(item) for key, item in value.items()}
    if isinstance(value, (list, tuple)):
        return [_safe(item) for item in value]
    if isinstance(value, np.integer):
        return int(value)
    if isinstance(value, np.floating):
        return float(value)
    return value


def split_frames(
    frame: pd.DataFrame,
    *,
    seed: int = SEED,
    validation_seed: int = VALIDATION_SEED,
    test_fraction: float = TEST_FRACTION,
    validation_fraction: float = VALIDATION_FRACTION,
) -> tuple[pd.DataFrame, pd.DataFrame, pd.DataFrame, dict[str, Any]]:
    """Return the frozen, group-safe train/validation/test split."""
    train_pool, test = assign_split(
        frame,
        test_fraction=test_fraction,
        seed=seed,
    )
    train, validation = assign_split(
        train_pool,
        test_fraction=validation_fraction,
        seed=validation_seed,
    )

    for name, part in (
        ("train", train),
        ("validation", validation),
        ("test", test),
    ):
        breeds = {
            (str(category), str(breed))
            for category, breed in part[
                ["livestock_type", "breed"]
            ].itertuples(index=False, name=None)
        }
        if breeds != {
            (category, breed)
            for category, values in SUPPORTED_BREEDS.items()
            for breed in values
        }:
            raise DatasetValidationError(
                f"{name} split does not contain all 20 breeds"
            )
        if part.empty:
            raise DatasetValidationError(f"{name} split is empty")

    overlap = {
        "train_test": len(
            set(feature_group_keys(train)) & set(feature_group_keys(test))
        ),
        "train_validation": len(
            set(feature_group_keys(train)) & set(feature_group_keys(validation))
        ),
        "validation_test": len(
            set(feature_group_keys(validation)) & set(feature_group_keys(test))
        ),
    }
    if any(overlap.values()):
        raise DatasetValidationError(
            f"Feature groups cross split boundaries: {overlap}"
        )

    split = {
        "seed": seed,
        "validation_seed": validation_seed,
        "test_fraction": test_fraction,
        "validation_fraction_of_pool": validation_fraction,
        "rows": {
            "train": int(len(train)),
            "validation": int(len(validation)),
            "test": int(len(test)),
        },
        "counts_by_category": {
            category: {
                "train": int((train["livestock_type"] == category).sum()),
                "validation": int(
                    (validation["livestock_type"] == category).sum()
                ),
                "test": int((test["livestock_type"] == category).sum()),
            }
            for category in sorted(SUPPORTED_BREEDS)
        },
        "breed_counts": {
            f"{category}/{breed}": {
                "train": int(
                    ((train["livestock_type"] == category) & (
                        train["breed"] == breed
                    )).sum()
                ),
                "validation": int(
                    ((validation["livestock_type"] == category) & (
                        validation["breed"] == breed
                    )).sum()
                ),
                "test": int(
                    ((test["livestock_type"] == category) & (
                        test["breed"] == breed
                    )).sum()
                ),
            }
            for category, values in SUPPORTED_BREEDS.items()
            for breed in values
        },
        "feature_group_overlap": overlap,
    }
    return train, validation, test, split


def _unique_model_path(version: str) -> Path:
    MODELS_DIR.mkdir(parents=True, exist_ok=True)
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
    path = MODELS_DIR / f"candidate_catboost_{version}_{stamp}.cbm"
    suffix = 1
    while path.exists():
        path = MODELS_DIR / (
            f"candidate_catboost_{version}_{stamp}_{suffix}.cbm"
        )
        suffix += 1
    return path


def train_candidate(
    dataset_path: Path = DEFAULT_DATASET,
    *,
    version: str = MODEL_VERSION,
    provenance: str,
    expected_rows: int = EXPECTED_ROWS,
    expected_per_breed: int = EXPECTED_PER_BREED,
    seed: int = SEED,
    iterations: int = ITERATIONS,
    depth: int = DEPTH,
    learning_rate: float = LEARNING_RATE,
    l2_leaf_reg: float = L2_LEAF_REG,
    thread_count: int = THREAD_COUNT,
) -> tuple[Path, Path, dict[str, Any]]:
    if provenance not in ("synthetic", "real"):
        raise DatasetValidationError(
            "Provenance must be given explicitly as 'synthetic' or 'real'."
        )
    if not version or not version.strip():
        raise DatasetValidationError("A model version label is required.")

    frame, dataset_summary = load_and_validate_dataset(dataset_path)
    if dataset_summary["rows_after_exact_duplicate_removal"] != expected_rows:
        raise DatasetValidationError(
            f"The {version} dataset must have {expected_rows} unique rows; "
            f"found {dataset_summary['rows_after_exact_duplicate_removal']}."
        )

    audit = _expected_audit(
        frame,
        expected_rows=expected_rows,
        expected_per_breed=expected_per_breed,
    )
    train_frame, validation_frame, test_frame, split = split_frames(frame)
    split["dataset_filename"] = dataset_summary["filename"]
    split["dataset_sha256"] = dataset_summary["sha256"]

    model = build_model(
        seed=seed,
        iterations=iterations,
        depth=depth,
        learning_rate=learning_rate,
        l2_leaf_reg=l2_leaf_reg,
        thread_count=thread_count,
    )
    model.fit(
        train_frame.loc[:, list(FEATURE_COLUMNS)],
        train_frame[TARGET_COLUMN],
        cat_features=list(CATEGORICAL_FEATURES),
        verbose=False,
    )

    validation_predictions = np.asarray(
        model.predict(validation_frame.loc[:, list(FEATURE_COLUMNS)]),
        dtype=float,
    )
    test_predictions = np.asarray(
        model.predict(test_frame.loc[:, list(FEATURE_COLUMNS)]),
        dtype=float,
    )
    baseline_predictions, baseline_rates, baseline_global_rate = (
        median_price_per_kg_baseline(train_frame, test_frame)
    )

    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
    model_path = _unique_model_path(version)
    model.save_model(str(model_path))

    metadata = build_training_profile(
        train_frame,
        model_file=model_path.name,
        provenance=provenance,
    )
    metadata.update(
        {
            "model_version": version,
            "dataset_label": DATASET_LABEL,
            "split": split,
        }
    )
    save_training_profile(model_path, metadata)

    safety = build_safety_profile(
        train_frame,
        model_file=model_path.name,
        provenance=provenance,
    )
    safety.update(
        {
            "model_version": version,
            "dataset_label": DATASET_LABEL,
        }
    )
    safety_path = save_safety_profile(model_path, safety)

    params = {
        "loss_function": "MAE",
        "eval_metric": "MAE",
        "iterations": iterations,
        "depth": depth,
        "learning_rate": learning_rate,
        "l2_leaf_reg": l2_leaf_reg,
        "random_seed": seed,
        "thread_count": thread_count,
        "cat_features": list(CATEGORICAL_FEATURES),
    }

    report: dict[str, Any] = {
        "generated_at_utc": datetime.now(timezone.utc).strftime(
            "%Y-%m-%dT%H:%M:%SZ"
        ),
        "model": {
            "version": version,
            "file": model_path.name,
            "sha256": sha256_file(model_path),
            "metadata_file": model_path.with_suffix(".metadata.json").name,
            "safety_profile_file": safety_path.name,
            "parameters": params,
            "feature_schema": {
                "features": list(FEATURE_COLUMNS),
                "categorical": list(CATEGORICAL_FEATURES),
                "target": TARGET_COLUMN,
                "target_unit": "PHP",
            },
        },
        "dataset": {
            **dataset_summary,
            "audit": audit,
            "provenance": provenance,
            "provenance_label": DATASET_LABEL,
        },
        "split": split,
        "validation": _evaluate(validation_frame, validation_predictions),
        "test": _evaluate(test_frame, test_predictions),
        "baseline": {
            **_evaluate(test_frame, baseline_predictions),
            "training_category_rates_php_per_kg": {
                category: round(rate, 4)
                for category, rate in baseline_rates.items()
            },
            "training_global_rate_php_per_kg": round(baseline_global_rate, 4),
        },
        "safety": {
            "validation": _safety_counts(validation_frame, safety),
            "test": _safety_counts(test_frame, safety),
            "metadata_ood_rows": {
                "validation": _metadata_ood_count(validation_frame, metadata),
                "test": _metadata_ood_count(test_frame, metadata),
            },
        },
        "warning": WARNING,
        "limitations": [
            "The dataset is synthetic and corrected for v5.",
            "No metric establishes real Trinidad/Bohol market accuracy.",
            "The candidate is not registered as active by this script.",
            "Model selection must use the validation split; the test split is "
            "touched once.",
        ],
    }

    REPORTS_DIR.mkdir(parents=True, exist_ok=True)
    dataset_manifest_path = (
        REPORTS_DIR / f"{version}_dataset_manifest_{stamp}.json"
    )
    dataset_manifest_path.write_text(
        json.dumps(
            _safe(
                {
                    "dataset": dataset_summary,
                    "audit": audit,
                    "provenance": provenance,
                    "provenance_label": DATASET_LABEL,
                    "warning": WARNING,
                }
            ),
            indent=2,
            ensure_ascii=False,
        )
        + "\n",
        encoding="utf-8",
    )
    split_manifest_path = REPORTS_DIR / f"{version}_split_manifest_{stamp}.json"
    split_manifest_path.write_text(
        json.dumps(_safe(split), indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )
    report["reports"] = {
        "training": (REPORTS_DIR / f"candidate_{version}_training_{stamp}.json")
        .relative_to(REPORTS_DIR)
        .as_posix(),
        "dataset_manifest": dataset_manifest_path.relative_to(
            REPORTS_DIR
        ).as_posix(),
        "split_manifest": split_manifest_path.relative_to(REPORTS_DIR).as_posix(),
    }
    report_path = REPORTS_DIR / f"candidate_{version}_training_{stamp}.json"
    report_path.write_text(
        json.dumps(_safe(report), indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )
    return model_path, report_path, report


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Train a CatBoost candidate without changing the active model."
        )
    )
    parser.add_argument("--dataset", type=Path, default=DEFAULT_DATASET)
    parser.add_argument("--version", default=MODEL_VERSION)
    parser.add_argument(
        "--provenance",
        choices=("synthetic", "real"),
        required=True,
        help="Explicit dataset provenance. Never inferred for new datasets.",
    )
    parser.add_argument("--expected-rows", type=int, default=EXPECTED_ROWS)
    parser.add_argument(
        "--expected-per-breed", type=int, default=EXPECTED_PER_BREED
    )
    parser.add_argument("--seed", type=int, default=SEED)
    parser.add_argument("--iterations", type=int, default=ITERATIONS)
    parser.add_argument("--depth", type=int, default=DEPTH)
    parser.add_argument("--learning-rate", type=float, default=LEARNING_RATE)
    parser.add_argument("--l2-leaf-reg", type=float, default=L2_LEAF_REG)
    parser.add_argument("--thread-count", type=int, default=THREAD_COUNT)
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    try:
        model_path, report_path, report = train_candidate(
            args.dataset,
            version=args.version,
            provenance=args.provenance,
            expected_rows=args.expected_rows,
            expected_per_breed=args.expected_per_breed,
            seed=args.seed,
            iterations=args.iterations,
            depth=args.depth,
            learning_rate=args.learning_rate,
            l2_leaf_reg=args.l2_leaf_reg,
            thread_count=args.thread_count,
        )
    except (DatasetValidationError, FileNotFoundError, ValueError) as exc:
        print(f"Candidate training failed: {exc}")
        return 1

    print(f"Candidate model: {model_path}")
    print(f"Training report: {report_path}")
    print(
        "Test MAE/RMSE/MAPE/R2: "
        f"{report['test']['overall']['mae']:.2f} / "
        f"{report['test']['overall']['rmse']:.2f} / "
        f"{report['test']['overall']['mape_percent']:.2f}% / "
        f"{report['test']['overall']['r2']:.4f}"
    )
    print("Active model unchanged.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
