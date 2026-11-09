"""Validate the saved prototype model and analyse its held-out errors.

This script does not tune or retrain. It reconstructs the Phase 2 split, loads
the existing v1 model, writes its training-distribution sidecar if missing,
and produces:

    reports/error_analysis.json
    reports/prediction_validation.json

The Phase 2 model and reports/metrics.json are not overwritten.
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
    FEATURE_COLUMNS,
    SUPPORTED_BREEDS,
    TARGET_COLUMN,
    InputValidationError,
    validate_feature_values,
)
from predict import load_model
from train import (
    DEFAULT_DATASET,
    MODELS_DIR,
    REPORTS_DIR,
    assign_split,
    load_and_validate_dataset,
    median_price_per_kg_baseline,
    per_category_metrics,
    regression_metrics,
)
from validation import (
    build_training_profile,
    out_of_distribution_warnings,
    save_training_profile,
)

PHASE2_SEED = 42
PHASE2_TEST_FRACTION = 0.2
SYNTHETIC_WARNING = (
    "Synthetic data only. The analysis demonstrates prototype behaviour, not "
    "verified real-market price accuracy."
)


def load_phase2_split(
    dataset_path: Path,
) -> tuple[pd.DataFrame, pd.DataFrame, pd.DataFrame, dict[str, Any]]:
    """Rebuild the exact Phase 2 train/test split without retraining."""
    frame, dataset_summary = load_and_validate_dataset(dataset_path)
    train, test = assign_split(
        frame,
        test_fraction=PHASE2_TEST_FRACTION,
        seed=PHASE2_SEED,
    )
    return frame, train, test, dataset_summary


def load_v1_model() -> tuple[CatBoostRegressor, Path, dict[str, Any]]:
    """Load the model referenced by the preserved Phase 2 metrics report."""
    report_path = REPORTS_DIR / "metrics.json"
    if not report_path.is_file():
        raise FileNotFoundError(
            f"Phase 2 metrics not found: {report_path}. Run `python train.py` first."
        )

    report = json.loads(report_path.read_text(encoding="utf-8"))
    model_file = report["model"]["file"]
    model_path = MODELS_DIR / model_file
    if not model_path.is_file():
        raise FileNotFoundError(f"Phase 2 model not found: {model_path}")

    model, path = load_model(model_path)
    return model, path, report


def _json_safe(value: Any) -> Any:
    """Convert numpy scalars to native Python values before JSON serialization."""
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


def _predict_values(
    model: CatBoostRegressor,
    values: dict[str, Any],
) -> float:
    frame = pd.DataFrame([values], columns=list(FEATURE_COLUMNS))
    prediction = float(model.predict(frame)[0])
    if not np.isfinite(prediction) or prediction <= 0:
        raise ValueError("Model returned a non-positive or non-finite price.")
    return prediction


def _median_inputs(
    train: pd.DataFrame,
    category: str,
    *,
    breed: str | None = None,
    sex: str = "male",
) -> dict[str, Any]:
    subset = train[train["livestock_type"] == category]
    if breed is not None:
        subset = subset[subset["breed"] == breed]
    if subset.empty:
        raise ValueError(f"No training rows for {category}/{breed}.")

    return {
        "livestock_type": category,
        "breed": breed or str(subset["breed"].mode().iloc[0]),
        "sex": sex,
        "age_months": float(subset["age_months"].median()),
        "weight_kg": float(subset["weight_kg"].median()),
    }


def _correlation(x: list[float], y: list[float]) -> float | None:
    if len(x) < 2 or len(y) < 2:
        return None
    if len(set(x)) < 2 or len(set(y)) < 2:
        return None
    value = float(np.corrcoef(np.asarray(x), np.asarray(y))[0, 1])
    return None if not np.isfinite(value) else round(value, 4)


def build_error_analysis(
    model: CatBoostRegressor,
    model_path: Path,
    train: pd.DataFrame,
    test: pd.DataFrame,
    dataset_summary: dict[str, Any],
) -> dict[str, Any]:
    """Compare the model with the training-only baseline on held-out rows."""
    actual = test[TARGET_COLUMN].to_numpy(dtype=float)
    predictions = _predict_frame(model, test)
    baseline_predictions, baseline_rates, baseline_global_rate = (
        median_price_per_kg_baseline(train, test)
    )

    catboost_per_category = per_category_metrics(test, predictions)
    baseline_per_category = per_category_metrics(test, baseline_predictions)

    per_breed: dict[str, dict[str, Any]] = {}
    for (category, breed), group in test.groupby(
        ["livestock_type", "breed"], sort=True
    ):
        positions = group.index.to_numpy()
        metrics = regression_metrics(
            group[TARGET_COLUMN].to_numpy(dtype=float),
            predictions[positions],
        )
        per_breed[f"{category}/{breed}"] = {
            "category": str(category),
            "breed": str(breed),
            "n": int(len(group)),
            **metrics,
        }

    residual_frame = test.copy()
    residual_frame["predicted_price"] = predictions
    residual_frame["baseline_price"] = baseline_predictions
    residual_frame["signed_error"] = predictions - actual
    residual_frame["absolute_error"] = np.abs(predictions - actual)
    residual_frame["absolute_percentage_error"] = (
        np.abs(predictions - actual) / actual * 100
    )

    residual_stats: dict[str, dict[str, Any]] = {}
    for category in sorted(catboost_per_category):
        subset = residual_frame[residual_frame["livestock_type"] == category]
        residual_stats[category] = {
            "n": int(len(subset)),
            "mean_signed_error_php": round(float(subset["signed_error"].mean()), 4),
            "median_absolute_error_php": round(
                float(subset["absolute_error"].median()), 4
            ),
            "p90_absolute_error_php": round(
                float(subset["absolute_error"].quantile(0.9)), 4
            ),
            "max_absolute_error_php": round(
                float(subset["absolute_error"].max()), 4
            ),
            "underprediction_count": int((subset["signed_error"] < 0).sum()),
            "overprediction_count": int((subset["signed_error"] > 0).sum()),
        }

    top_errors = (
        residual_frame.sort_values("absolute_error", ascending=False)
        .head(12)
        .loc[
            :,
            [
                "livestock_type",
                "breed",
                "sex",
                "age_months",
                "weight_kg",
                TARGET_COLUMN,
                "predicted_price",
                "baseline_price",
                "signed_error",
                "absolute_error",
                "absolute_percentage_error",
            ],
        ]
        .to_dict(orient="records")
    )

    categories_by_error = sorted(
        catboost_per_category,
        key=lambda category: catboost_per_category[category]["mae"],
        reverse=True,
    )
    model_wins = [
        category
        for category in sorted(catboost_per_category)
        if catboost_per_category[category]["mae"]
        < baseline_per_category[category]["mae"]
    ]
    findings = [
        "Highest CatBoost MAE categories: "
        + ", ".join(
            f"{category} (PHP {catboost_per_category[category]['mae']:,.2f})"
            for category in categories_by_error[:3]
        )
        + ".",
        "CatBoost has lower MAE than the price/kg baseline for: "
        + (", ".join(model_wins) if model_wins else "none")
        + ".",
        "The baseline is stronger overall on MAE and RMSE; CatBoost is stronger "
        "on MAPE and on several low-price categories. The synthetic target is "
        "strongly weight-driven, which favours the baseline.",
    ]

    return {
        "generated_at_utc": datetime.now(timezone.utc).strftime(
            "%Y-%m-%dT%H:%M:%SZ"
        ),
        "model_file": model_path.name,
        "dataset": {
            "filename": dataset_summary["filename"],
            "sha256": dataset_summary["sha256"],
            "provenance": dataset_summary["provenance"]
            if "provenance" in dataset_summary
            else "synthetic",
        },
        "split": {
            "phase2_seed": PHASE2_SEED,
            "test_fraction": PHASE2_TEST_FRACTION,
            "train_rows": int(len(train)),
            "test_rows": int(len(test)),
            "test_categories": sorted(
                str(value) for value in test["livestock_type"].unique()
            ),
        },
        "overall": {
            "catboost": regression_metrics(actual, predictions),
            "baseline_median_price_per_kg": regression_metrics(
                actual, baseline_predictions
            ),
        },
        "per_category": {
            "catboost": catboost_per_category,
            "baseline_median_price_per_kg": baseline_per_category,
        },
        "residual_stats": residual_stats,
        "per_breed": per_breed,
        "top_absolute_errors": top_errors,
        "baseline_training_rates_php_per_kg": {
            category: round(rate, 4)
            for category, rate in baseline_rates.items()
        },
        "baseline_training_global_rate_php_per_kg": round(
            baseline_global_rate, 4
        ),
        "findings": findings,
        "warning": SYNTHETIC_WARNING,
    }


def build_prediction_validation(
    model: CatBoostRegressor,
    model_path: Path,
    train: pd.DataFrame,
    profile: dict[str, Any],
) -> dict[str, Any]:
    """Exercise every breed and measure sensitivity to each feature."""
    breed_predictions: list[dict[str, Any]] = []
    for category in sorted(SUPPORTED_BREEDS):
        for breed in SUPPORTED_BREEDS[category]:
            subset = train[
                (train["livestock_type"] == category) & (train["breed"] == breed)
            ]
            if subset.empty:
                continue
            values = _median_inputs(train, category, breed=breed)
            price = _predict_values(model, values)
            breed_predictions.append(
                {
                    "livestock_type": category,
                    "breed": breed,
                    "sex": values["sex"],
                    "age_months": values["age_months"],
                    "weight_kg": values["weight_kg"],
                    "predicted_price_php": round(price, 2),
                }
            )

    weight_sensitivity: dict[str, Any] = {}
    age_sensitivity: dict[str, Any] = {}
    sex_sensitivity: dict[str, Any] = {}

    for category in sorted(SUPPORTED_BREEDS):
        subset = train[train["livestock_type"] == category]
        age = float(subset["age_months"].median())
        weight = float(subset["weight_kg"].median())
        breed = str(subset["breed"].mode().iloc[0])

        weight_points = sorted(
            {
                round(float(value), 4)
                for value in subset["weight_kg"].quantile(
                    [0.1, 0.25, 0.5, 0.75, 0.9]
                )
            }
        )
        weight_predictions = [
            _predict_values(
                model,
                {
                    "livestock_type": category,
                    "breed": breed,
                    "sex": "male",
                    "age_months": age,
                    "weight_kg": point,
                },
            )
            for point in weight_points
        ]
        weight_sensitivity[category] = {
            "breed_used": breed,
            "weights_kg": weight_points,
            "predicted_prices_php": [
                round(value, 2) for value in weight_predictions
            ],
            "correlation": _correlation(weight_points, weight_predictions),
            "change_percent_low_to_high": round(
                (weight_predictions[-1] - weight_predictions[0])
                / weight_predictions[0]
                * 100,
                4,
            ),
        }

        age_points = sorted(
            {
                round(float(value), 4)
                for value in subset["age_months"].quantile([0.1, 0.5, 0.9])
            }
        )
        age_predictions = [
            _predict_values(
                model,
                {
                    "livestock_type": category,
                    "breed": breed,
                    "sex": "male",
                    "age_months": point,
                    "weight_kg": weight,
                },
            )
            for point in age_points
        ]
        age_sensitivity[category] = {
            "breed_used": breed,
            "ages_months": age_points,
            "predicted_prices_php": [round(value, 2) for value in age_predictions],
            "correlation": _correlation(age_points, age_predictions),
            "change_percent_low_to_high": round(
                (age_predictions[-1] - age_predictions[0])
                / age_predictions[0]
                * 100,
                4,
            ),
        }

        base_values = {
            "livestock_type": category,
            "breed": breed,
            "sex": "male",
            "age_months": age,
            "weight_kg": weight,
        }
        male_price = _predict_values(model, base_values)
        female_price = _predict_values(
            model, {**base_values, "sex": "female"}
        )
        sex_sensitivity[category] = {
            "breed_used": breed,
            "age_months": age,
            "weight_kg": weight,
            "male_price_php": round(male_price, 2),
            "female_price_php": round(female_price, 2),
            "absolute_difference_php": round(abs(male_price - female_price), 2),
            "difference_percent": round(
                abs(male_price - female_price) / male_price * 100,
                4,
            ),
        }

    breed_sensitivity: dict[str, Any] = {}
    for category in sorted(SUPPORTED_BREEDS):
        category_rows = train[train["livestock_type"] == category]
        age = float(category_rows["age_months"].median())
        weight = float(category_rows["weight_kg"].median())
        prices: dict[str, float] = {}
        for breed in SUPPORTED_BREEDS[category]:
            if (train["breed"] == breed).any():
                prices[breed] = _predict_values(
                    model,
                    {
                        "livestock_type": category,
                        "breed": breed,
                        "sex": "male",
                        "age_months": age,
                        "weight_kg": weight,
                    },
                )
        if prices:
            values = list(prices.values())
            breed_sensitivity[category] = {
                "age_months": age,
                "weight_kg": weight,
                "prices_php": {
                    breed: round(price, 2) for breed, price in prices.items()
                },
                "min_price_php": round(min(values), 2),
                "max_price_php": round(max(values), 2),
                "spread_percent": round(
                    (max(values) - min(values)) / min(values) * 100,
                    4,
                ),
            }

    invalid_cases = {
        "unsupported_category": {
            "livestock_type": "sheep",
            "breed": "merino",
            "sex": "male",
            "age_months": 24,
            "weight_kg": 50,
        },
        "unsupported_breed_for_category": {
            "livestock_type": "cattle",
            "breed": "boer",
            "sex": "male",
            "age_months": 24,
            "weight_kg": 50,
        },
        "invalid_sex": {
            "livestock_type": "cattle",
            "breed": "brahman",
            "sex": "unknown",
            "age_months": 24,
            "weight_kg": 50,
        },
        "zero_age": {
            "livestock_type": "cattle",
            "breed": "brahman",
            "sex": "male",
            "age_months": 0,
            "weight_kg": 50,
        },
        "negative_weight": {
            "livestock_type": "cattle",
            "breed": "brahman",
            "sex": "male",
            "age_months": 24,
            "weight_kg": -1,
        },
        "age_above_training_ceiling": {
            "livestock_type": "cattle",
            "breed": "brahman",
            "sex": "male",
            "age_months": 301,
            "weight_kg": 50,
        },
    }
    invalid_results: dict[str, Any] = {}
    for name, values in invalid_cases.items():
        try:
            validate_feature_values(**values)
            rejected = False
            message = None
        except InputValidationError as exc:
            rejected = True
            message = str(exc)
        invalid_results[name] = {
            "input": values,
            "rejected": rejected,
            "message": message,
        }

    base_values = _median_inputs(train, "cattle", breed="brahman")
    observed_ranges = profile["feature_ranges"]
    ood_cases = {
        "weight_below_training_min": {
            **base_values,
            "weight_kg": float(observed_ranges["weight_kg"]["min"]) * 0.5,
        },
        "weight_above_training_max": {
            **base_values,
            "weight_kg": float(observed_ranges["weight_kg"]["max"]) * 1.5,
        },
        "age_above_training_max": {
            **base_values,
            "age_months": float(observed_ranges["age_months"]["max"]) + 1,
        },
    }
    ood_results = {
        name: {
            "input": values,
            "warnings": out_of_distribution_warnings(values, profile),
        }
        for name, values in ood_cases.items()
    }

    return {
        "generated_at_utc": datetime.now(timezone.utc).strftime(
            "%Y-%m-%dT%H:%M:%SZ"
        ),
        "model_file": model_path.name,
        "training_profile_available": True,
        "supported_categories": sorted(SUPPORTED_BREEDS),
        "supported_breed_count": sum(
            len(breeds) for breeds in SUPPORTED_BREEDS.values()
        ),
        "all_breed_predictions_positive": all(
            row["predicted_price_php"] > 0 for row in breed_predictions
        ),
        "breed_predictions": breed_predictions,
        "weight_sensitivity": weight_sensitivity,
        "age_sensitivity": age_sensitivity,
        "sex_sensitivity": sex_sensitivity,
        "breed_sensitivity": breed_sensitivity,
        "invalid_inputs": invalid_results,
        "out_of_distribution_examples": ood_results,
        "warning": SYNTHETIC_WARNING,
    }


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Validate the saved prototype model and analyse errors."
    )
    parser.add_argument(
        "--dataset",
        type=Path,
        default=DEFAULT_DATASET,
        help="Dataset used to reconstruct the Phase 2 split.",
    )
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)

    try:
        _, train, test, dataset_summary = load_phase2_split(args.dataset)
        model, model_path, _ = load_v1_model()
    except (FileNotFoundError, ValueError) as exc:
        print(f"Evaluation failed: {exc}", file=sys.stderr)
        return 1

    profile = build_training_profile(
        train,
        model_file=model_path.name,
        provenance="synthetic",
    )
    save_training_profile(model_path, profile)

    error_report = build_error_analysis(
        model,
        model_path,
        train,
        test,
        dataset_summary,
    )
    prediction_report = build_prediction_validation(
        model,
        model_path,
        train,
        profile,
    )

    REPORTS_DIR.mkdir(parents=True, exist_ok=True)
    error_path = REPORTS_DIR / "error_analysis.json"
    prediction_path = REPORTS_DIR / "prediction_validation.json"
    error_path.write_text(
        json.dumps(_json_safe(error_report), indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )
    prediction_path.write_text(
        json.dumps(
            _json_safe(prediction_report), indent=2, ensure_ascii=False
        )
        + "\n",
        encoding="utf-8",
    )

    overall = error_report["overall"]
    print(f"Model:  {model_path}")
    print(f"Error analysis: {error_path}")
    print(f"Prediction validation: {prediction_path}")
    print(
        "Held-out overall  "
        f"CatBoost MAE={overall['catboost']['mae']:,.2f}, "
        f"RMSE={overall['catboost']['rmse']:,.2f}, "
        f"MAPE={overall['catboost']['mape_percent']:.2f}%  |  "
        f"baseline MAE={overall['baseline_median_price_per_kg']['mae']:,.2f}, "
        f"RMSE={overall['baseline_median_price_per_kg']['rmse']:,.2f}, "
        f"MAPE={overall['baseline_median_price_per_kg']['mape_percent']:.2f}%"
    )
    print("\nPer-category CatBoost / baseline MAE")
    for category in sorted(error_report["per_category"]["catboost"]):
        model_mae = error_report["per_category"]["catboost"][category]["mae"]
        baseline_mae = error_report["per_category"][
            "baseline_median_price_per_kg"
        ][category]["mae"]
        print(
            f"  {category:<10} {model_mae:>12,.2f} / {baseline_mae:>12,.2f}"
        )

    print("\nFeature sensitivity")
    for category in sorted(prediction_report["weight_sensitivity"]):
        weight = prediction_report["weight_sensitivity"][category]
        age = prediction_report["age_sensitivity"][category]
        print(
            f"  {category:<10} weight corr={weight['correlation']}, "
            f"weight change={weight['change_percent_low_to_high']:.1f}%, "
            f"age corr={age['correlation']}"
        )

    ood_hits = sum(
        1
        for result in prediction_report["out_of_distribution_examples"].values()
        if result["warnings"]
    )
    rejected = sum(
        1
        for result in prediction_report["invalid_inputs"].values()
        if result["rejected"]
    )
    print(
        f"\nInvalid inputs rejected: {rejected}/"
        f"{len(prediction_report['invalid_inputs'])}; "
        f"OOD examples warned: {ood_hits}/"
        f"{len(prediction_report['out_of_distribution_examples'])}"
    )
    print(f"\n{SYNTHETIC_WARNING}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
