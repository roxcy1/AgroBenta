"""Train and evaluate a young-chicken CatBoost candidate without touching v1.

Leakage-safe design:
- Reconstruct the original Phase 2 split (seed 42). Its 400 test rows stay
  untouched.
- Split the 140 young-chicken rows into 100 train / 40 test, grouped by feature
  combination and stratified by breed, checking every age band is held out.
- Train the candidate on original train (1,597) + young train (100).
- Evaluate on original test (400), young test (40), and older chicken rows.

The candidate uses the v1 hyperparameters so the dataset extension is the only
change. It is saved with a candidate filename and is not selected automatically
by ``predict.py``.
"""

from __future__ import annotations

import argparse
import json
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import numpy as np
import pandas as pd
from catboost import CatBoostRegressor

from features import (
    CATEGORICAL_FEATURES,
    FEATURE_COLUMNS,
    SUPPORTED_BREEDS,
    TARGET_COLUMN,
    InputValidationError,
    validate_feature_values,
)
from generate_young_chicken_dataset import (
    AGE_BANDS,
    DAYS_PER_MONTH,
    curve_weight_kg,
)
from predict import load_model, predict
from train import (
    DEFAULT_DEPTH,
    DEFAULT_ITERATIONS,
    DEFAULT_L2_LEAF_REG,
    DEFAULT_LEARNING_RATE,
    DEFAULT_SEED,
    MODELS_DIR,
    REPORTS_DIR,
    SYNTHETIC_WARNING,
    assign_split,
    build_model,
    feature_group_keys,
    load_and_validate_dataset,
    median_price_per_kg_baseline,
    per_category_metrics,
    regression_metrics,
    sha256_file,
    split_summary,
)
from validation import (
    build_training_profile,
    out_of_distribution_warnings,
    save_training_profile,
)

BASE_DIR = Path(__file__).resolve().parent
ORIGINAL_DATASET = BASE_DIR / "data" / "synthetic_livestock_sales.csv"
EXPANDED_DATASET = BASE_DIR / "data" / "synthetic_livestock_sales_v2.csv"
PHASE2_SEED = 42
PHASE2_TEST_FRACTION = 0.2
YOUNG_TEST_SIZE = 40
YOUNG_SPLIT_SEED_START = 2026
CANDIDATE_VERSION = "v2-young-chicken"
CANDIDATE_PREFIX = "candidate_catboost_young_chicken_v2"
REPORT_PATH = REPORTS_DIR / "young_chicken_training_v2.json"
VALIDATION_REPORT_PATH = REPORTS_DIR / "young_chicken_prediction_validation_v2.json"

AGE_BAND_NAMES = [band[0] for band in AGE_BANDS]
AGE_BAND_LABELS = {
    "1-7_days": "1-7 days",
    "8-14_days": "8-14 days",
    "15-21_days": "15-21 days",
    "22-30_days": "22-30 days",
}
CONTROLLED_WEIGHT_KG = 0.5


def age_band(age_months: float) -> str | None:
    """Map a fractional age to the generated young-chicken band.

    Exactly 1.0 month is older chicken (30.4375 days) and is not part of the
    young-chicken generation bands.
    """
    months = float(age_months)
    if months <= 0 or months >= 1.0:
        return None
    days = int(round(months * DAYS_PER_MONTH))
    if 1 <= days <= 7:
        return "1-7_days"
    if 8 <= days <= 14:
        return "8-14_days"
    if 15 <= days <= 21:
        return "15-21_days"
    if 22 <= days <= 30:
        return "22-30_days"
    return None


def split_young_chickens(
    young: pd.DataFrame,
) -> tuple[pd.DataFrame, pd.DataFrame, int]:
    """Choose 40 held-out young rows, covering every age band."""
    test_fraction = YOUNG_TEST_SIZE / len(young)
    for seed in range(YOUNG_SPLIT_SEED_START, YOUNG_SPLIT_SEED_START + 100):
        train, test = assign_split(
            young,
            test_fraction=test_fraction,
            seed=seed,
        )
        if len(test) != YOUNG_TEST_SIZE:
            continue
        bands = {
            band
            for band in test["age_months"].map(age_band).tolist()
            if band is not None
        }
        if bands == set(AGE_BAND_NAMES):
            return train, test, seed

    raise RuntimeError(
        "Could not create a 40-row young-chicken test set covering every age band."
    )


def _json_safe(value: Any) -> Any:
    if isinstance(value, dict):
        return {key: _json_safe(item) for key, item in value.items()}
    if isinstance(value, list):
        return [_json_safe(item) for item in value]
    if isinstance(value, tuple):
        return [_json_safe(item) for item in value]
    if isinstance(value, np.integer):
        return int(value)
    if isinstance(value, np.floating):
        return float(value)
    if isinstance(value, np.bool_):
        return bool(value)
    return value


def _predict_frame(model: CatBoostRegressor, frame: pd.DataFrame) -> np.ndarray:
    return np.asarray(
        model.predict(frame.loc[:, list(FEATURE_COLUMNS)]),
        dtype=float,
    )


def _predict_values(model: CatBoostRegressor, values: dict[str, Any]) -> float:
    frame = pd.DataFrame([values], columns=list(FEATURE_COLUMNS))
    prediction = float(model.predict(frame)[0])
    if not np.isfinite(prediction) or prediction <= 0:
        raise ValueError("Model returned a non-positive or non-finite price.")
    return prediction


def _median_inputs(
    frame: pd.DataFrame,
    category: str,
    breed: str,
    sex: str = "male",
) -> dict[str, Any]:
    subset = frame[
        (frame["livestock_type"] == category) & (frame["breed"] == breed)
    ]
    return {
        "livestock_type": category,
        "breed": breed,
        "sex": sex,
        "age_months": float(subset["age_months"].median()),
        "weight_kg": float(subset["weight_kg"].median()),
    }


def _subset_metrics(
    frame: pd.DataFrame,
    candidate_predictions: np.ndarray,
    v1_predictions: np.ndarray,
    baseline_predictions: np.ndarray,
) -> dict[str, Any]:
    actual = frame[TARGET_COLUMN].to_numpy(dtype=float)
    return {
        "rows": int(len(frame)),
        "candidate": regression_metrics(actual, candidate_predictions),
        "v1": regression_metrics(actual, v1_predictions),
        "baseline_median_price_per_kg": regression_metrics(
            actual, baseline_predictions
        ),
    }


def _category_comparison(
    frame: pd.DataFrame,
    candidate_predictions: np.ndarray,
    v1_predictions: np.ndarray,
    baseline_predictions: np.ndarray,
) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for category in sorted(frame["livestock_type"].unique()):
        mask = (frame["livestock_type"] == category).to_numpy()
        result[str(category)] = _subset_metrics(
            frame.loc[mask].reset_index(drop=True),
            candidate_predictions[mask],
            v1_predictions[mask],
            baseline_predictions[mask],
        )
    return result


def _band_comparison(
    frame: pd.DataFrame,
    candidate_predictions: np.ndarray,
    v1_predictions: np.ndarray,
    baseline_predictions: np.ndarray,
) -> dict[str, Any]:
    bands = frame["age_months"].map(age_band)
    result: dict[str, Any] = {}
    for band in AGE_BAND_NAMES:
        mask = (bands == band).to_numpy()
        if not mask.any():
            result[band] = {
                "label": AGE_BAND_LABELS[band],
                "rows": 0,
            }
            continue
        result[band] = {
            "label": AGE_BAND_LABELS[band],
            **_subset_metrics(
                frame.loc[mask].reset_index(drop=True),
                candidate_predictions[mask],
                v1_predictions[mask],
                baseline_predictions[mask],
            ),
        }
    return result


def _breakdown(frame: pd.DataFrame) -> dict[str, Any]:
    band_counts: dict[str, int] = {}
    for band in AGE_BAND_NAMES:
        band_counts[band] = int(
            (frame["age_months"].map(age_band) == band).sum()
        )
    breed_sex = {
        f"{breed}/{sex}": int(count)
        for (breed, sex), count in frame.groupby(["breed", "sex"]).size().items()
    }
    return {
        "rows": int(len(frame)),
        "age_band_counts": band_counts,
        "breed_counts": {
            str(breed): int(count)
            for breed, count in frame["breed"].value_counts().sort_index().items()
        },
        "breed_sex_counts": breed_sex,
    }


def _controlled_predictions(
    model: CatBoostRegressor,
    v1_model: CatBoostRegressor,
) -> dict[str, Any]:
    """Predict days 3/10/20/30 at fixed breed, sex and weight."""
    results: dict[str, Any] = {}
    for breed in SUPPORTED_BREEDS["chicken"]:
        breed_results: dict[str, Any] = {}
        for day in (3, 10, 20, 30):
            values = {
                "livestock_type": "chicken",
                "breed": breed,
                "sex": "male",
                "age_months": day / DAYS_PER_MONTH,
                "weight_kg": CONTROLLED_WEIGHT_KG,
            }
            breed_results[f"{day}_days"] = {
                "age_months": round(day / DAYS_PER_MONTH, 6),
                "weight_kg": CONTROLLED_WEIGHT_KG,
                "candidate_price_php": round(_predict_values(model, values), 2),
                "v1_price_php": round(_predict_values(v1_model, values), 2),
            }
        results[breed] = breed_results
    return results


def _age_consistent_predictions(
    model: CatBoostRegressor,
    v1_model: CatBoostRegressor,
) -> dict[str, Any]:
    results: dict[str, Any] = {}
    for day in (3, 10, 20, 30):
        weight = curve_weight_kg("broiler", day, "male")
        values = {
            "livestock_type": "chicken",
            "breed": "broiler",
            "sex": "male",
            "age_months": day / DAYS_PER_MONTH,
            "weight_kg": round(weight, 2),
        }
        results[f"{day}_days"] = {
            "age_months": round(day / DAYS_PER_MONTH, 6),
            "weight_kg": round(weight, 2),
            "candidate_price_php": round(_predict_values(model, values), 2),
            "v1_price_php": round(_predict_values(v1_model, values), 2),
        }
    return results


def _invalid_input_results() -> dict[str, Any]:
    cases = {
        "unsupported_category": {
            "livestock_type": "sheep",
            "breed": "merino",
            "sex": "male",
            "age_months": 0.1,
            "weight_kg": 0.2,
        },
        "unsupported_breed_for_category": {
            "livestock_type": "cattle",
            "breed": "boer",
            "sex": "male",
            "age_months": 12,
            "weight_kg": 100,
        },
        "invalid_sex": {
            "livestock_type": "chicken",
            "breed": "broiler",
            "sex": "unknown",
            "age_months": 0.1,
            "weight_kg": 0.2,
        },
        "zero_age": {
            "livestock_type": "chicken",
            "breed": "broiler",
            "sex": "male",
            "age_months": 0,
            "weight_kg": 0.2,
        },
        "negative_weight": {
            "livestock_type": "chicken",
            "breed": "broiler",
            "sex": "male",
            "age_months": 0.1,
            "weight_kg": -1,
        },
        "age_above_ceiling": {
            "livestock_type": "chicken",
            "breed": "broiler",
            "sex": "male",
            "age_months": 301,
            "weight_kg": 1,
        },
    }
    result: dict[str, Any] = {}
    for name, values in cases.items():
        try:
            validate_feature_values(**values)
            result[name] = {"rejected": False, "message": None}
        except InputValidationError as exc:
            result[name] = {"rejected": True, "message": str(exc)}
    return result


def _ood_results(profile: dict[str, Any]) -> dict[str, Any]:
    base = _median_inputs(
        pd.DataFrame(
            [
                {
                    "livestock_type": "chicken",
                    "breed": "broiler",
                    "sex": "male",
                    "age_months": 0.5,
                    "weight_kg": 1.0,
                    TARGET_COLUMN: 200.0,
                }
            ]
        ),
        "chicken",
        "broiler",
    )
    ranges = profile["feature_ranges"]
    cases = {
        "weight_below_training_min": {
            **base,
            "weight_kg": float(ranges["weight_kg"]["min"]) * 0.5,
        },
        "weight_above_training_max": {
            **base,
            "weight_kg": float(ranges["weight_kg"]["max"]) * 1.5,
        },
        "age_above_training_max": {
            **base,
            "age_months": float(ranges["age_months"]["max"]) + 1,
        },
    }
    return {
        name: {
            "input": values,
            "warnings": out_of_distribution_warnings(values, profile),
        }
        for name, values in cases.items()
    }


def _recommendation(
    original_v1_metrics: dict[str, float],
    original_candidate_metrics: dict[str, float],
    young_v1_metrics: dict[str, float],
    young_candidate_metrics: dict[str, float],
    original_category_comparison: dict[str, Any],
) -> dict[str, Any]:
    young_improvement = (
        (young_v1_metrics["mae"] - young_candidate_metrics["mae"])
        / young_v1_metrics["mae"]
        * 100
    )
    original_change = (
        (original_candidate_metrics["mae"] - original_v1_metrics["mae"])
        / original_v1_metrics["mae"]
        * 100
    )
    category_changes = {
        category: round(
            (
                values["candidate"]["mae"]
                - values["v1"]["mae"]
            )
            / values["v1"]["mae"]
            * 100,
            4,
        )
        for category, values in original_category_comparison.items()
    }
    worst_category_change = max(category_changes.values())
    consider = (
        young_improvement >= 20.0
        and original_change <= 2.0
        and worst_category_change <= 5.0
    )
    return {
        "consider_v2": consider,
        "young_chicken_mae_improvement_percent": round(young_improvement, 4),
        "original_test_mae_change_percent": round(original_change, 4),
        "original_category_mae_change_percent": category_changes,
        "worst_original_category_change_percent": worst_category_change,
        "rule": (
            "Consider v2 only if young-chicken MAE improves by at least 20%, "
            "the original-test MAE changes by no more than 2%, and no original "
            "category MAE degrades by more than 5%. v2 is not promoted here."
        ),
    }


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Train and evaluate the young-chicken CatBoost candidate."
    )
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    parse_args(argv)

    try:
        original_frame, original_summary = load_and_validate_dataset(
            ORIGINAL_DATASET
        )
        original_train, original_test = assign_split(
            original_frame,
            test_fraction=PHASE2_TEST_FRACTION,
            seed=PHASE2_SEED,
        )

        expanded_frame, expanded_summary = load_and_validate_dataset(
            EXPANDED_DATASET
        )
        young_frame = expanded_frame[
            (expanded_frame["livestock_type"] == "chicken")
            & (expanded_frame["age_months"] < 1.0)
        ].reset_index(drop=True)
        if len(young_frame) != 140:
            raise RuntimeError(
                f"Expected 140 young-chicken rows, found {len(young_frame)}."
            )

        young_train, young_test, young_split_seed = split_young_chickens(
            young_frame
        )
        v2_train = pd.concat(
            [original_train, young_train], ignore_index=True
        )

        original_test_keys = set(feature_group_keys(original_test))
        young_test_keys = set(feature_group_keys(young_test))
        v2_train_keys = set(feature_group_keys(v2_train))
        if original_test_keys & v2_train_keys:
            raise RuntimeError(
                "Leakage: original test feature groups are in v2 training data."
            )
        if young_test_keys & v2_train_keys:
            raise RuntimeError(
                "Leakage: young test feature groups are in v2 training data."
            )
        if young_test_keys & original_test_keys:
            raise RuntimeError(
                "Leakage: young test and original test feature groups overlap."
            )

        v1_report = json.loads(
            (REPORTS_DIR / "metrics.json").read_text(encoding="utf-8")
        )
        v1_model, v1_path = load_model(
            MODELS_DIR / v1_report["model"]["file"]
        )
    except (FileNotFoundError, RuntimeError, ValueError) as exc:
        print(f"Candidate training failed: {exc}", file=sys.stderr)
        return 1

    print(
        f"Original split: train={len(original_train)}, test={len(original_test)}"
    )
    print(
        f"Young split: train={len(young_train)}, test={len(young_test)}, "
        f"seed={young_split_seed}"
    )
    print(f"Candidate training rows: {len(v2_train)}")

    candidate = build_model(
        seed=DEFAULT_SEED,
        iterations=DEFAULT_ITERATIONS,
        depth=DEFAULT_DEPTH,
        learning_rate=DEFAULT_LEARNING_RATE,
        l2_leaf_reg=DEFAULT_L2_LEAF_REG,
    )
    candidate.fit(
        v2_train.loc[:, list(FEATURE_COLUMNS)],
        v2_train[TARGET_COLUMN],
        cat_features=list(CATEGORICAL_FEATURES),
        verbose=False,
    )

    candidate_original = _predict_frame(candidate, original_test)
    v1_original = _predict_frame(v1_model, original_test)
    original_baseline, original_rates, original_global = (
        median_price_per_kg_baseline(original_train, original_test)
    )

    candidate_young = _predict_frame(candidate, young_test)
    v1_young = _predict_frame(v1_model, young_test)
    young_baseline, young_rates, young_global = median_price_per_kg_baseline(
        v2_train, young_test
    )

    older_chicken = original_test[
        original_test["livestock_type"] == "chicken"
    ].reset_index(drop=True)
    older_candidate = _predict_frame(candidate, older_chicken)
    older_v1 = _predict_frame(v1_model, older_chicken)
    older_baseline, _, _ = median_price_per_kg_baseline(
        original_train, older_chicken
    )

    original_comparison = _subset_metrics(
        original_test,
        candidate_original,
        v1_original,
        original_baseline,
    )
    original_by_category = _category_comparison(
        original_test,
        candidate_original,
        v1_original,
        original_baseline,
    )
    young_comparison = _subset_metrics(
        young_test,
        candidate_young,
        v1_young,
        young_baseline,
    )
    young_by_band = _band_comparison(
        young_test,
        candidate_young,
        v1_young,
        young_baseline,
    )
    older_comparison = _subset_metrics(
        older_chicken,
        older_candidate,
        older_v1,
        older_baseline,
    )
    recommendation = _recommendation(
        original_comparison["v1"],
        original_comparison["candidate"],
        young_comparison["v1"],
        young_comparison["candidate"],
        original_by_category,
    )

    controlled = _controlled_predictions(candidate, v1_model)
    age_consistent = _age_consistent_predictions(candidate, v1_model)

    MODELS_DIR.mkdir(parents=True, exist_ok=True)
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
    model_path = MODELS_DIR / f"{CANDIDATE_PREFIX}_{stamp}.cbm"
    candidate.save_model(str(model_path))

    profile = build_training_profile(
        v2_train,
        model_file=model_path.name,
        provenance="synthetic",
    )
    save_training_profile(model_path, profile)

    # Verify a fresh load, not the in-memory object.
    loaded, loaded_path = load_model(model_path)
    reload_prediction = predict(
        livestock_type="chicken",
        breed="broiler",
        sex="male",
        age_months=10 / DAYS_PER_MONTH,
        weight_kg=0.5,
        model=loaded,
        model_path=loaded_path,
    )
    all_positive = all(
        _predict_values(
            loaded,
            _median_inputs(v2_train, category, breed),
        )
        > 0
        for category in sorted(SUPPORTED_BREEDS)
        for breed in SUPPORTED_BREEDS[category]
    )
    invalid_inputs = _invalid_input_results()
    ood = _ood_results(profile)

    report: dict[str, Any] = {
        "generated_at_utc": datetime.now(timezone.utc).strftime(
            "%Y-%m-%dT%H:%M:%SZ"
        ),
        "candidate": {
            "version": CANDIDATE_VERSION,
            "file": model_path.name,
            "sha256": sha256_file(model_path),
            "trained_at_utc": datetime.now(timezone.utc).strftime(
                "%Y-%m-%dT%H:%M:%SZ"
            ),
            "parameters": {
                "loss_function": "MAE",
                "eval_metric": "MAE",
                "iterations": DEFAULT_ITERATIONS,
                "depth": DEFAULT_DEPTH,
                "learning_rate": DEFAULT_LEARNING_RATE,
                "l2_leaf_reg": DEFAULT_L2_LEAF_REG,
                "random_seed": DEFAULT_SEED,
                "cat_features": list(CATEGORICAL_FEATURES),
            },
            "feature_schema": {
                "features": list(FEATURE_COLUMNS),
                "categorical": list(CATEGORICAL_FEATURES),
                "numeric": ["age_months", "weight_kg"],
                "target": TARGET_COLUMN,
                "target_unit": "PHP",
            },
            "supported_categories": sorted(SUPPORTED_BREEDS),
            "supported_breeds": {
                category: list(breeds)
                for category, breeds in SUPPORTED_BREEDS.items()
            },
            "training_rows": int(len(v2_train)),
        },
        "dataset": {
            "original": {
                "filename": original_summary["filename"],
                "sha256": original_summary["sha256"],
                "raw_rows": original_summary["rows_loaded"],
                "rows_after_deduplication": original_summary[
                    "rows_after_exact_duplicate_removal"
                ],
            },
            "expanded": {
                "filename": expanded_summary["filename"],
                "sha256": expanded_summary["sha256"],
                "raw_rows": expanded_summary["rows_loaded"],
                "rows_after_deduplication": expanded_summary[
                    "rows_after_exact_duplicate_removal"
                ],
                "young_chicken_breakdown": _breakdown(young_frame),
            },
            "backup_file": "synthetic_livestock_sales_v1_backup.csv",
            "manifest": "reports/young_chicken_dataset_manifest.json",
        },
        "split": {
            "phase2_seed": PHASE2_SEED,
            "phase2_test_fraction": PHASE2_TEST_FRACTION,
            "original_train_rows": int(len(original_train)),
            "original_test_rows": int(len(original_test)),
            "young_split_seed": young_split_seed,
            "young_train_rows": int(len(young_train)),
            "young_test_rows": int(len(young_test)),
            "v2_train_rows": int(len(v2_train)),
            "young_test_breakdown": _breakdown(young_test),
            "young_test_categories": sorted(
                str(value) for value in young_test["livestock_type"].unique()
            ),
            "leakage_checks": {
                "original_test_groups_in_v2_train": len(
                    original_test_keys & v2_train_keys
                ),
                "young_test_groups_in_v2_train": len(
                    young_test_keys & v2_train_keys
                ),
                "young_test_groups_in_original_test": len(
                    young_test_keys & original_test_keys
                ),
            },
        },
        "evaluation": {
            "original_test_400": {
                **original_comparison,
                "by_category": original_by_category,
            },
            "young_chicken_test_40": {
                **young_comparison,
                "by_age_band": young_by_band,
            },
            "older_chicken_test": older_comparison,
            "young_chicken_baseline_training_rates": {
                category: round(rate, 4)
                for category, rate in young_rates.items()
            },
        },
        "age_predictions": {
            "controlled_diagnostic": {
                "note": (
                    "Breed, sex and weight are held fixed at 0.5 kg for the "
                    "age-effect comparison. A 0.5 kg 3-day-old bird is not a "
                    "realistic weight; this is a controlled diagnostic only."
                ),
                "by_breed": controlled,
            },
            "age_consistent_broiler_male": age_consistent,
        },
        "recommendation": recommendation,
        "warning": SYNTHETIC_WARNING,
    }

    validation_report: dict[str, Any] = {
        "generated_at_utc": datetime.now(timezone.utc).strftime(
            "%Y-%m-%dT%H:%M:%SZ"
        ),
        "candidate_file": model_path.name,
        "model_reload_ok": reload_prediction.price > 0,
        "model_reload_prediction_php": round(reload_prediction.price, 2),
        "all_20_breed_predictions_positive": all_positive,
        "invalid_inputs": invalid_inputs,
        "out_of_distribution_examples": ood,
        "warning": SYNTHETIC_WARNING,
    }

    REPORTS_DIR.mkdir(parents=True, exist_ok=True)
    REPORT_PATH.write_text(
        json.dumps(_json_safe(report), indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )
    VALIDATION_REPORT_PATH.write_text(
        json.dumps(_json_safe(validation_report), indent=2, ensure_ascii=False)
        + "\n",
        encoding="utf-8",
    )

    print(f"\nCandidate model: {model_path}")
    print(f"Training report: {REPORT_PATH}")
    print(f"Validation report: {VALIDATION_REPORT_PATH}")
    print("\nOriginal test (400 rows), MAE / RMSE / MAPE")
    for label in ("candidate", "v1", "baseline_median_price_per_kg"):
        metrics = original_comparison[label]
        print(
            f"  {label:<30} {metrics['mae']:>10,.2f} "
            f"{metrics['rmse']:>10,.2f} {metrics['mape_percent']:>8.2f}%"
        )
    print("\nYoung chicken test (40 rows), MAE / RMSE / MAPE")
    for label in ("candidate", "v1", "baseline_median_price_per_kg"):
        metrics = young_comparison[label]
        print(
            f"  {label:<30} {metrics['mae']:>10,.2f} "
            f"{metrics['rmse']:>10,.2f} {metrics['mape_percent']:>8.2f}%"
        )
    print("\nYoung test by age band (candidate MAE / v1 MAE)")
    for band in AGE_BAND_NAMES:
        values = young_by_band[band]
        if values["rows"]:
            print(
                f"  {AGE_BAND_LABELS[band]:<12} "
                f"{values['candidate']['mae']:>10,.2f} / "
                f"{values['v1']['mae']:>10,.2f}"
            )
    print("\nControlled age predictions, broiler male at 0.5 kg")
    for day in ("3_days", "10_days", "20_days", "30_days"):
        row = controlled["broiler"][day]
        print(
            f"  {day:<9} v2 PHP {row['candidate_price_php']:>8,.2f}  "
            f"v1 PHP {row['v1_price_php']:>8,.2f}"
        )
    print(
        f"\nRecommendation: {'consider v2 for young-chicken coverage' if recommendation['consider_v2'] else 'retain v1'}"
    )
    print(recommendation["rule"])
    print(f"\n{SYNTHETIC_WARNING}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
