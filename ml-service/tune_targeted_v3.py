"""Targeted improvement of the young-chicken v2 candidate.

Only the Phase 4 training pool is used for validation selection. The original
400-row test and the 40-row young-chicken test remain untouched until the final
evaluation.

Experiments cover:
- sample weighting of young and older chickens,
- deterministic undersampling of young training rows,
- a small depth/iteration learning-rate grid.

A candidate is saved only if the final held-out acceptance criteria pass.
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
from generate_young_chicken_dataset import DAYS_PER_MONTH, curve_weight_kg
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
    load_and_validate_dataset,
    median_price_per_kg_baseline,
    per_category_metrics,
    regression_metrics,
    sha256_file,
)
from train_young_chicken import (
    AGE_BAND_NAMES,
    age_band,
    split_young_chickens,
)
from validation import (
    build_training_profile,
    out_of_distribution_warnings,
    save_training_profile,
)

BASE_DIR = Path(__file__).resolve().parent
ORIGINAL_DATASET = BASE_DIR / "data" / "synthetic_livestock_sales.csv"
EXPANDED_DATASET = BASE_DIR / "data" / "synthetic_livestock_sales_v2.csv"
V1_REPORT = REPORTS_DIR / "metrics.json"
V2_REPORT = REPORTS_DIR / "young_chicken_training_v2.json"
REPORT_PATH = REPORTS_DIR / "targeted_improvement_v3.json"
VALIDATION_REPORT_PATH = REPORTS_DIR / "targeted_prediction_validation_v3.json"

PHASE2_SEED = 42
VALIDATION_FRACTION = 0.2
VALIDATION_SEED_START = 2026
CANDIDATE_VERSION = "v3-targeted"
CANDIDATE_PREFIX = "candidate_catboost_targeted_v3"
CONTROLLED_WEIGHT_KG = 0.5
# Execution-only setting; the model seed and hyperparameters remain fixed.
TUNING_THREAD_COUNT = 4

# v2 acceptance reference points from Phase 4.
V2_OLDER_MAE = 55.3248
V2_YOUNG_MAE = 6.6134
V2_ORIGINAL_MAE = 2968.6087
V1_OLDER_MAE = 48.4922

TRIALS: list[dict[str, Any]] = [
    {
        "id": "v2_reference",
        "weights": "none",
        "sample": "full",
        "iterations": DEFAULT_ITERATIONS,
        "depth": DEFAULT_DEPTH,
        "learning_rate": DEFAULT_LEARNING_RATE,
        "l2_leaf_reg": DEFAULT_L2_LEAF_REG,
    },
    {
        "id": "young_0.5",
        "weights": "young_0.5",
        "sample": "full",
        "iterations": DEFAULT_ITERATIONS,
        "depth": DEFAULT_DEPTH,
        "learning_rate": DEFAULT_LEARNING_RATE,
        "l2_leaf_reg": DEFAULT_L2_LEAF_REG,
    },
    {
        "id": "young_0.25",
        "weights": "young_0.25",
        "sample": "full",
        "iterations": DEFAULT_ITERATIONS,
        "depth": DEFAULT_DEPTH,
        "learning_rate": DEFAULT_LEARNING_RATE,
        "l2_leaf_reg": DEFAULT_L2_LEAF_REG,
    },
    {
        "id": "older_1.5",
        "weights": "older_1.5",
        "sample": "full",
        "iterations": DEFAULT_ITERATIONS,
        "depth": DEFAULT_DEPTH,
        "learning_rate": DEFAULT_LEARNING_RATE,
        "l2_leaf_reg": DEFAULT_L2_LEAF_REG,
    },
    {
        "id": "older_2.0",
        "weights": "older_2.0",
        "sample": "full",
        "iterations": DEFAULT_ITERATIONS,
        "depth": DEFAULT_DEPTH,
        "learning_rate": DEFAULT_LEARNING_RATE,
        "l2_leaf_reg": DEFAULT_L2_LEAF_REG,
    },
    {
        "id": "young_0.5_older_1.5",
        "weights": "young_0.5_older_1.5",
        "sample": "full",
        "iterations": DEFAULT_ITERATIONS,
        "depth": DEFAULT_DEPTH,
        "learning_rate": DEFAULT_LEARNING_RATE,
        "l2_leaf_reg": DEFAULT_L2_LEAF_REG,
    },
    {
        "id": "older_2.0_young_1.05",
        "weights": "older_2.0_young_1.05",
        "sample": "full",
        "iterations": DEFAULT_ITERATIONS,
        "depth": DEFAULT_DEPTH,
        "learning_rate": DEFAULT_LEARNING_RATE,
        "l2_leaf_reg": DEFAULT_L2_LEAF_REG,
    },
    {
        "id": "young_0.25_older_1.5",
        "weights": "young_0.25_older_1.5",
        "sample": "full",
        "iterations": DEFAULT_ITERATIONS,
        "depth": DEFAULT_DEPTH,
        "learning_rate": DEFAULT_LEARNING_RATE,
        "l2_leaf_reg": DEFAULT_L2_LEAF_REG,
    },
    {
        "id": "depth8_i1000",
        "weights": "none",
        "sample": "full",
        "iterations": 1000,
        "depth": 8,
        "learning_rate": 0.05,
        "l2_leaf_reg": 5.0,
    },
    {
        "id": "young_undersample_50",
        "weights": "none",
        "sample": "young_50",
        "iterations": DEFAULT_ITERATIONS,
        "depth": DEFAULT_DEPTH,
        "learning_rate": DEFAULT_LEARNING_RATE,
        "l2_leaf_reg": DEFAULT_L2_LEAF_REG,
    },
    {
        "id": "young_undersample_70",
        "weights": "none",
        "sample": "young_70",
        "iterations": DEFAULT_ITERATIONS,
        "depth": DEFAULT_DEPTH,
        "learning_rate": DEFAULT_LEARNING_RATE,
        "l2_leaf_reg": DEFAULT_L2_LEAF_REG,
    },
]


def _is_young_chicken(frame: pd.DataFrame) -> pd.Series:
    return (frame["livestock_type"] == "chicken") & (frame["age_months"] < 1.0)


def _is_older_chicken(frame: pd.DataFrame) -> pd.Series:
    return (frame["livestock_type"] == "chicken") & (frame["age_months"] >= 1.0)


def sample_weights(frame: pd.DataFrame, strategy: str) -> np.ndarray:
    """Return CatBoost sample weights for a named strategy."""
    weights = np.ones(len(frame), dtype=float)
    young = _is_young_chicken(frame).to_numpy()
    older = _is_older_chicken(frame).to_numpy()

    if strategy == "none":
        return weights
    if strategy == "young_0.5":
        weights[young] = 0.5
    elif strategy == "young_0.25":
        weights[young] = 0.25
    elif strategy == "older_1.5":
        weights[older] = 1.5
    elif strategy == "older_2.0":
        weights[older] = 2.0
    elif strategy == "young_0.5_older_1.5":
        weights[young] = 0.5
        weights[older] = 1.5
    elif strategy == "young_0.25_older_1.5":
        weights[young] = 0.25
        weights[older] = 1.5
    elif strategy == "older_2.0_young_1.05":
        weights[older] = 2.0
        weights[young] = 1.05
    else:
        raise ValueError(f"Unknown weight strategy: {strategy}")
    return weights


def sample_training_frame(
    frame: pd.DataFrame,
    strategy: str,
    seed: int,
) -> pd.DataFrame:
    """Apply deterministic young-row undersampling when requested."""
    young_mask = _is_young_chicken(frame)
    if strategy == "full":
        return frame.reset_index(drop=True)

    if strategy in ("young_50", "young_70"):
        keep_count = 50 if strategy == "young_50" else 70
        young = frame.loc[young_mask]
        if len(young) > keep_count:
            young = young.sample(n=keep_count, random_state=seed)
        other = frame.loc[~young_mask]
        return pd.concat([other, young], ignore_index=True).sort_values(
            by=list(FEATURE_COLUMNS)
        ).reset_index(drop=True)

    raise ValueError(f"Unknown sampling strategy: {strategy}")


def _metrics(frame: pd.DataFrame, predictions: np.ndarray) -> dict[str, Any]:
    return regression_metrics(
        frame[TARGET_COLUMN].to_numpy(dtype=float), predictions
    )


def _subset_metrics(
    frame: pd.DataFrame,
    predictions: np.ndarray,
    mask: pd.Series,
) -> dict[str, Any]:
    selected = frame.loc[mask].reset_index(drop=True)
    return {
        "rows": int(len(selected)),
        **_metrics(selected, predictions[mask.to_numpy()]),
    }


def evaluate_validation(
    model: CatBoostRegressor,
    validation: pd.DataFrame,
) -> dict[str, Any]:
    predictions = np.asarray(
        model.predict(validation.loc[:, list(FEATURE_COLUMNS)]), dtype=float
    )
    older = _is_older_chicken(validation)
    young = _is_young_chicken(validation)
    non_chicken = validation["livestock_type"] != "chicken"

    return {
        "overall": _metrics(validation, predictions),
        "older_chicken": _subset_metrics(validation, predictions, older),
        "young_chicken": _subset_metrics(validation, predictions, young),
        "per_category": per_category_metrics(validation, predictions),
        "non_chicken_overall": _subset_metrics(
            validation, predictions, non_chicken
        ),
    }


def fit_trial(
    trial: dict[str, Any],
    train: pd.DataFrame,
    seed: int = DEFAULT_SEED,
) -> CatBoostRegressor:
    sampled = sample_training_frame(train, trial["sample"], seed)
    weights = sample_weights(sampled, trial["weights"])
    model = build_model(
        seed=seed,
        iterations=int(trial["iterations"]),
        depth=int(trial["depth"]),
        learning_rate=float(trial["learning_rate"]),
        l2_leaf_reg=float(trial["l2_leaf_reg"]),
        thread_count=TUNING_THREAD_COUNT,
    )
    model.fit(
        sampled.loc[:, list(FEATURE_COLUMNS)],
        sampled[TARGET_COLUMN],
        cat_features=list(CATEGORICAL_FEATURES),
        sample_weight=weights,
        verbose=False,
    )
    return model


def find_validation_split(
    v2_train: pd.DataFrame,
) -> tuple[pd.DataFrame, pd.DataFrame, int]:
    for seed in range(VALIDATION_SEED_START, VALIDATION_SEED_START + 100):
        train, validation = assign_split(
            v2_train,
            test_fraction=VALIDATION_FRACTION,
            seed=seed,
        )
        young_count = int(_is_young_chicken(validation).sum())
        older_count = int(_is_older_chicken(validation).sum())
        if young_count >= 15 and older_count >= 45:
            return train, validation, seed
    raise RuntimeError("No validation split contained enough chicken rows.")


def selection_decision(
    reference: dict[str, Any],
    trials: list[dict[str, Any]],
) -> dict[str, Any]:
    """Select the lowest older-chicken validation MAE under guardrails.

    ``reference`` is the full reference trial record, including its
    ``validation`` metrics.
    """
    reference_metrics = reference["validation"]
    reference_young = reference_metrics["young_chicken"]["mae"]
    reference_overall = reference_metrics["overall"]["mae"]
    reference_categories = reference_metrics["per_category"]

    eligible: list[dict[str, Any]] = []
    for trial in trials:
        if trial["id"] == reference["id"]:
            continue
        metrics = trial["validation"]
        young_ok = metrics["young_chicken"]["mae"] <= reference_young * 1.10
        overall_ok = metrics["overall"]["mae"] <= reference_overall * 1.02
        category_ok = all(
            metrics["per_category"][category]["mae"]
            <= reference_categories[category]["mae"] * 1.10
            for category in reference_categories
        )
        if young_ok and overall_ok and category_ok:
            eligible.append(trial)

    selected = (
        min(
            eligible,
            key=lambda trial: (
                trial["validation"]["older_chicken"]["mae"],
                trial["validation"]["overall"]["mae"],
            ),
        )
        if eligible
        else reference
    )
    return {
        "selected_trial_id": selected["id"],
        "selection_eligible": bool(eligible),
        "eligible_trial_ids": [trial["id"] for trial in eligible],
        "rule": (
            "Select the lowest older-chicken validation MAE among trials whose "
            "young-chicken MAE is within 10% of v2 reference, overall "
            "validation MAE is within 2%, and no category MAE is more than 10% "
            "worse on validation. Final acceptance uses the stricter 5% test "
            "guard because validation category subsets are small."
        ),
    }


def acceptance(
    candidate_original: dict[str, Any],
    candidate_young: dict[str, Any],
    candidate_per_category: dict[str, Any],
    v2_per_category: dict[str, Any],
) -> dict[str, Any]:
    older_mae = candidate_original["by_category"]["chicken"]["mae"]
    young_mae = candidate_young["overall"]["mae"]
    older_pass = older_mae <= V1_OLDER_MAE
    young_pass = young_mae <= V2_YOUNG_MAE * 1.10

    category_failures = []
    for category in ("cattle", "carabao", "goat", "swine"):
        candidate_mae = candidate_per_category[category]["mae"]
        reference_mae = v2_per_category[category]["mae"]
        if candidate_mae > reference_mae * 1.05:
            category_failures.append(
                {
                    "category": category,
                    "candidate_mae": round(candidate_mae, 4),
                    "v2_mae": round(reference_mae, 4),
                    "change_percent": round(
                        (candidate_mae - reference_mae) / reference_mae * 100,
                        4,
                    ),
                }
            )

    overall_not_worse = (
        candidate_original["overall"]["mae"] <= V2_ORIGINAL_MAE
    )
    return {
        "older_chicken_mae": round(older_mae, 4),
        "older_chicken_target": V1_OLDER_MAE,
        "older_chicken_pass": older_pass,
        "young_chicken_mae": round(young_mae, 4),
        "young_chicken_limit": round(V2_YOUNG_MAE * 1.10, 4),
        "young_chicken_pass": young_pass,
        "non_chicken_regressions": category_failures,
        "non_chicken_pass": not category_failures,
        "overall_original_mae": round(
            candidate_original["overall"]["mae"], 4
        ),
        "v2_original_mae": V2_ORIGINAL_MAE,
        "overall_not_worse_than_v2": overall_not_worse,
        "accepted": older_pass and young_pass and not category_failures,
        "rule": (
            "Accept only if older-chicken MAE <= v1 (48.49), young-chicken MAE "
            "<= 7.27, and no cattle/carabao/goat/swine MAE is more than 5% "
            "worse than v2. Overall original-test MAE is a secondary target."
        ),
    }


def _controlled_predictions(
    models: dict[str, CatBoostRegressor],
) -> dict[str, Any]:
    results: dict[str, Any] = {}
    for day in (3, 10, 20, 30):
        values = {
            "livestock_type": "chicken",
            "breed": "broiler",
            "sex": "male",
            "age_months": day / DAYS_PER_MONTH,
            "weight_kg": CONTROLLED_WEIGHT_KG,
        }
        frame = pd.DataFrame([values], columns=list(FEATURE_COLUMNS))
        results[f"{day}_days"] = {
            "age_months": round(day / DAYS_PER_MONTH, 6),
            "weight_kg": CONTROLLED_WEIGHT_KG,
            **{
                f"{name}_price_php": round(float(model.predict(frame)[0]), 2)
                for name, model in models.items()
            },
        }
    return results


def _age_consistent_predictions(
    models: dict[str, CatBoostRegressor],
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
        frame = pd.DataFrame([values], columns=list(FEATURE_COLUMNS))
        results[f"{day}_days"] = {
            "age_months": round(day / DAYS_PER_MONTH, 6),
            "weight_kg": round(weight, 2),
            **{
                f"{name}_price_php": round(float(model.predict(frame)[0]), 2)
                for name, model in models.items()
            },
        }
    return results


def _invalid_inputs() -> dict[str, Any]:
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


def _ood_examples(profile: dict[str, Any]) -> dict[str, Any]:
    ranges = profile["feature_ranges"]
    base = {
        "livestock_type": "chicken",
        "breed": "broiler",
        "sex": "male",
        "age_months": 0.5,
        "weight_kg": 1.0,
    }
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


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    return argparse.ArgumentParser(
        description="Targeted v3 tuning for the older-chicken regression."
    ).parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    parse_args(argv)

    try:
        original, _ = load_and_validate_dataset(ORIGINAL_DATASET)
        original_train, original_test = assign_split(original, 0.2, 42)
        expanded, expanded_summary = load_and_validate_dataset(
            EXPANDED_DATASET
        )
        young = expanded[
            (expanded["livestock_type"] == "chicken")
            & (expanded["age_months"] < 1.0)
        ].reset_index(drop=True)
        young_train, young_test, young_seed = split_young_chickens(young)
        v2_train = pd.concat(
            [original_train, young_train], ignore_index=True
        )
        validation_train, validation, validation_seed = find_validation_split(
            v2_train
        )

        v1_report = json.loads(V1_REPORT.read_text(encoding="utf-8"))
        v1, _ = load_model(MODELS_DIR / v1_report["model"]["file"])
        v2_report = json.loads(V2_REPORT.read_text(encoding="utf-8"))
        v2_path = MODELS_DIR / v2_report["candidate"]["file"]
        v2, _ = load_model(v2_path)
    except (FileNotFoundError, RuntimeError, ValueError) as exc:
        print(f"Targeted tuning failed: {exc}", file=sys.stderr)
        return 1

    print(
        f"v2 training rows={len(v2_train)}; validation seed={validation_seed}; "
        f"validation rows={len(validation)} "
        f"(young={int(_is_young_chicken(validation).sum())}, "
        f"older chicken={int(_is_older_chicken(validation).sum())})"
    )

    trials: list[dict[str, Any]] = []
    for trial in TRIALS:
        print(f"  running {trial['id']} ...", flush=True)
        model = fit_trial(trial, validation_train)
        metrics = evaluate_validation(model, validation)
        record = {
            "id": trial["id"],
            "config": trial,
            "validation": metrics,
        }
        trials.append(record)
        print(
            f"    overall MAE={metrics['overall']['mae']:,.2f}; "
            f"older={metrics['older_chicken']['mae']:,.2f}; "
            f"young={metrics['young_chicken']['mae']:,.2f}",
            flush=True,
        )

    reference = next(trial for trial in trials if trial["id"] == "v2_reference")
    selection = selection_decision(reference, trials)
    selected = next(
        trial for trial in trials if trial["id"] == selection["selected_trial_id"]
    )
    print(f"\nSelected trial: {selected['id']}")

    # Final refit on the full Phase 4 training pool. No test data is used here.
    final_model = fit_trial(selected["config"], v2_train)
    candidate_original_predictions = np.asarray(
        final_model.predict(original_test.loc[:, list(FEATURE_COLUMNS)]),
        dtype=float,
    )
    candidate_young_predictions = np.asarray(
        final_model.predict(young_test.loc[:, list(FEATURE_COLUMNS)]),
        dtype=float,
    )
    v1_original = np.asarray(
        v1.predict(original_test.loc[:, list(FEATURE_COLUMNS)]), dtype=float
    )
    v2_original = np.asarray(
        v2.predict(original_test.loc[:, list(FEATURE_COLUMNS)]), dtype=float
    )
    v1_young = np.asarray(
        v1.predict(young_test.loc[:, list(FEATURE_COLUMNS)]), dtype=float
    )
    v2_young = np.asarray(
        v2.predict(young_test.loc[:, list(FEATURE_COLUMNS)]), dtype=float
    )

    older_test = original_test[
        original_test["livestock_type"] == "chicken"
    ].reset_index(drop=True)
    candidate_older = np.asarray(
        final_model.predict(older_test.loc[:, list(FEATURE_COLUMNS)]),
        dtype=float,
    )
    v1_older = np.asarray(
        v1.predict(older_test.loc[:, list(FEATURE_COLUMNS)]), dtype=float
    )
    v2_older = np.asarray(
        v2.predict(older_test.loc[:, list(FEATURE_COLUMNS)]), dtype=float
    )

    def comparison(
        frame: pd.DataFrame,
        candidate: np.ndarray,
        v1_pred: np.ndarray,
        v2_pred: np.ndarray,
        baseline: np.ndarray,
    ) -> dict[str, Any]:
        return {
            "rows": int(len(frame)),
            "candidate": _metrics(frame, candidate),
            "v1": _metrics(frame, v1_pred),
            "v2": _metrics(frame, v2_pred),
            "baseline_median_price_per_kg": _metrics(frame, baseline),
        }

    original_baseline, _, _ = median_price_per_kg_baseline(
        original_train, original_test
    )
    young_baseline, _, _ = median_price_per_kg_baseline(
        v2_train, young_test
    )
    older_baseline, _, _ = median_price_per_kg_baseline(
        original_train, older_test
    )

    original_comparison = comparison(
        original_test,
        candidate_original_predictions,
        v1_original,
        v2_original,
        original_baseline,
    )
    original_comparison["by_category"] = {
        category: comparison(
            original_test.loc[
                (original_test["livestock_type"] == category)
            ].reset_index(drop=True),
            candidate_original_predictions[
                (original_test["livestock_type"] == category).to_numpy()
            ],
            v1_original[
                (original_test["livestock_type"] == category).to_numpy()
            ],
            v2_original[
                (original_test["livestock_type"] == category).to_numpy()
            ],
            original_baseline[
                (original_test["livestock_type"] == category).to_numpy()
            ],
        )
        for category in sorted(original_test["livestock_type"].unique())
    }
    young_comparison = comparison(
        young_test,
        candidate_young_predictions,
        v1_young,
        v2_young,
        young_baseline,
    )
    older_comparison = comparison(
        older_test,
        candidate_older,
        v1_older,
        v2_older,
        older_baseline,
    )

    candidate_per_category = {
        category: values["candidate"]
        for category, values in original_comparison["by_category"].items()
    }
    v2_per_category = {
        category: values["v2"]
        for category, values in original_comparison["by_category"].items()
    }
    verdict = acceptance(
        {
            "overall": original_comparison["candidate"],
            "by_category": candidate_per_category,
        },
        {"overall": young_comparison["candidate"]},
        candidate_per_category,
        v2_per_category,
    )

    profile = build_training_profile(
        v2_train,
        model_file=f"{CANDIDATE_PREFIX}.cbm",
        provenance="synthetic",
    )
    controlled = _controlled_predictions(
        {"candidate": final_model, "v1": v1, "v2": v2}
    )
    age_consistent = _age_consistent_predictions(
        {"candidate": final_model, "v1": v1, "v2": v2}
    )
    invalid_inputs = _invalid_inputs()
    ood = _ood_examples(profile)

    model_path: Path | None = None
    reload_ok = False
    reload_price = None
    if verdict["accepted"]:
        MODELS_DIR.mkdir(parents=True, exist_ok=True)
        stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
        model_path = MODELS_DIR / f"{CANDIDATE_PREFIX}_{stamp}.cbm"
        final_model.save_model(str(model_path))
        profile = build_training_profile(
            v2_train, model_file=model_path.name, provenance="synthetic"
        )
        save_training_profile(model_path, profile)
        loaded, loaded_path = load_model(model_path)
        reload_result = predict(
            livestock_type="chicken",
            breed="broiler",
            sex="male",
            age_months=10 / DAYS_PER_MONTH,
            weight_kg=0.5,
            model=loaded,
            model_path=loaded_path,
        )
        reload_ok = reload_result.price > 0
        reload_price = round(reload_result.price, 2)

    all_breeds_positive = all(
        float(
            final_model.predict(
                pd.DataFrame(
                    [
                        {
                            "livestock_type": category,
                            "breed": breed,
                            "sex": "male",
                            "age_months": float(
                                v2_train.loc[
                                    (v2_train["livestock_type"] == category)
                                    & (v2_train["breed"] == breed),
                                    "age_months",
                                ].median()
                            ),
                            "weight_kg": float(
                                v2_train.loc[
                                    (v2_train["livestock_type"] == category)
                                    & (v2_train["breed"] == breed),
                                    "weight_kg",
                                ].median()
                            ),
                        }
                    ],
                    columns=list(FEATURE_COLUMNS),
                )
            )[0]
        )
        > 0
        for category in sorted(SUPPORTED_BREEDS)
        for breed in SUPPORTED_BREEDS[category]
    )

    report: dict[str, Any] = {
        "generated_at_utc": datetime.now(timezone.utc).strftime(
            "%Y-%m-%dT%H:%M:%SZ"
        ),
        "dataset": {
            "expanded_file": expanded_summary["filename"],
            "expanded_sha256": expanded_summary["sha256"],
            "v2_training_rows": int(len(v2_train)),
            "young_split_seed": young_seed,
            "young_train_rows": int(len(young_train)),
            "young_test_rows": int(len(young_test)),
        },
        "validation": {
            "seed": validation_seed,
            "train_rows": int(len(validation_train)),
            "validation_rows": int(len(validation)),
            "young_chicken_rows": int(_is_young_chicken(validation).sum()),
            "older_chicken_rows": int(_is_older_chicken(validation).sum()),
            "test_used_for_selection": False,
            "thread_count": TUNING_THREAD_COUNT,
            "trials": trials,
            "selection": selection,
        },
        "final_test": {
            "original_400": original_comparison,
            "young_chicken_40": young_comparison,
            "older_chicken_80": older_comparison,
        },
        "acceptance": verdict,
        "age_predictions": {
            "controlled_diagnostic_0_5kg": controlled,
            "age_consistent_broiler_male": age_consistent,
        },
        "saved_model": (
            {
                "file": model_path.name,
                "sha256": sha256_file(model_path),
                "version": CANDIDATE_VERSION,
                "parameters": {
                    **selected["config"],
                    "thread_count": TUNING_THREAD_COUNT,
                },
                "sidecar": str(model_path.with_suffix(".metadata.json").name),
            }
            if model_path is not None
            else None
        ),
        "warning": SYNTHETIC_WARNING,
    }

    validation_report: dict[str, Any] = {
        "generated_at_utc": datetime.now(timezone.utc).strftime(
            "%Y-%m-%dT%H:%M:%SZ"
        ),
        "candidate_saved": model_path is not None,
        "model_reload_ok": reload_ok,
        "model_reload_prediction_php": reload_price,
        "all_20_breed_predictions_positive": all_breeds_positive,
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

    print("\nFinal test comparison")
    for label in ("candidate", "v1", "v2", "baseline_median_price_per_kg"):
        metrics = original_comparison[label]
        print(
            f"  original {label:<28} MAE={metrics['mae']:>10,.2f} "
            f"RMSE={metrics['rmse']:>10,.2f} MAPE={metrics['mape_percent']:>7.2f}%"
        )
    print(
        f"  young candidate MAE={young_comparison['candidate']['mae']:.2f}; "
        f"v2={young_comparison['v2']['mae']:.2f}"
    )
    print(
        f"  older candidate MAE={older_comparison['candidate']['mae']:.2f}; "
        f"v1={older_comparison['v1']['mae']:.2f}; "
        f"v2={older_comparison['v2']['mae']:.2f}"
    )
    print(f"\nAcceptance: {'PASS' if verdict['accepted'] else 'FAIL'}")
    print(f"Older chicken pass: {verdict['older_chicken_pass']}")
    print(f"Young chicken pass: {verdict['young_chicken_pass']}")
    print(f"Non-chicken pass: {verdict['non_chicken_pass']}")
    print(f"Overall not worse than v2: {verdict['overall_not_worse_than_v2']}")
    if model_path is not None:
        print(f"Candidate saved: {model_path}")
    else:
        print("No candidate model saved (acceptance failed).")
    print(f"Report: {REPORT_PATH}")
    print(f"Validation report: {VALIDATION_REPORT_PATH}")
    print(f"\n{SYNTHETIC_WARNING}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
