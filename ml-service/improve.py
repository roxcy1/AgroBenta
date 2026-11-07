"""Controlled, leakage-safe CatBoost tuning.

Method:
1. Rebuild the Phase 2 train/test split (seed 42). The test set is untouched
   during every tuning decision.
2. Split the Phase 2 training pool into train/validation (group-safe).
3. Try a small, documented parameter grid on train, select on validation.
4. Refit the selected configuration on the full Phase 2 training pool.
5. Evaluate once on the untouched Phase 2 test set against v1 and the baseline.
6. Save v2 only when the final test MAE improves by at least 1%, MAPE does not
   worsen by more than 1%, and no category MAE degrades by more than 10%.

The Phase 2 model and reports/metrics.json are never overwritten.
"""

from __future__ import annotations

import argparse
import json
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import catboost
import numpy as np
import pandas as pd
from catboost import CatBoostRegressor

from features import (
    CATEGORICAL_FEATURES,
    FEATURE_COLUMNS,
    SUPPORTED_BREEDS,
    SUPPORTED_CATEGORIES,
    TARGET_COLUMN,
)
from predict import load_model
from train import (
    DEFAULT_DATASET,
    MODELS_DIR,
    REPORTS_DIR,
    SYNTHETIC_WARNING,
    assign_split,
    load_and_validate_dataset,
    median_price_per_kg_baseline,
    per_category_metrics,
    regression_metrics,
    sha256_file,
    split_summary,
)
from validation import build_training_profile, save_training_profile

PHASE2_SEED = 42
PHASE2_TEST_FRACTION = 0.2
VALIDATION_SEED_START = 2026
VALIDATION_FRACTION = 0.2
MODEL_VERSION = "v2"

SELECTION_RULE = (
    "Save v2 only if final held-out MAE improves by at least 1% versus v1, "
    "MAPE does not worsen by more than 1%, and no category MAE degrades by "
    "more than 10%."
)


def trial_configs() -> list[dict[str, Any]]:
    """Small documented grid. No test metrics are consulted here."""
    return [
        {
            "id": "v1_reference_mae_d6_i1000_lr05_l2_3",
            "loss_function": "MAE",
            "iterations": 1000,
            "depth": 6,
            "learning_rate": 0.05,
            "l2_leaf_reg": 3.0,
        },
        {
            "id": "mae_d8_i1000_lr05_l2_3",
            "loss_function": "MAE",
            "iterations": 1000,
            "depth": 8,
            "learning_rate": 0.05,
            "l2_leaf_reg": 3.0,
        },
        {
            "id": "mae_d6_i1500_lr03_l2_5",
            "loss_function": "MAE",
            "iterations": 1500,
            "depth": 6,
            "learning_rate": 0.03,
            "l2_leaf_reg": 5.0,
        },
        {
            "id": "mae_d4_i1500_lr05_l2_3",
            "loss_function": "MAE",
            "iterations": 1500,
            "depth": 4,
            "learning_rate": 0.05,
            "l2_leaf_reg": 3.0,
        },
        {
            "id": "mae_d6_i1000_lr05_l2_3_ctr1_ohe25",
            "loss_function": "MAE",
            "iterations": 1000,
            "depth": 6,
            "learning_rate": 0.05,
            "l2_leaf_reg": 3.0,
            "max_ctr_complexity": 1,
            "one_hot_max_size": 25,
        },
        {
            "id": "mae_d8_i1200_lr04_l2_5_ctr1_ohe25",
            "loss_function": "MAE",
            "iterations": 1200,
            "depth": 8,
            "learning_rate": 0.04,
            "l2_leaf_reg": 5.0,
            "max_ctr_complexity": 1,
            "one_hot_max_size": 25,
        },
        {
            "id": "rmse_d6_i1000_lr05_l2_3",
            "loss_function": "RMSE",
            "iterations": 1000,
            "depth": 6,
            "learning_rate": 0.05,
            "l2_leaf_reg": 3.0,
        },
    ]


def parameters_for(config: dict[str, Any], seed: int) -> dict[str, Any]:
    params: dict[str, Any] = {
        "loss_function": config["loss_function"],
        "eval_metric": "MAE",
        "iterations": config["iterations"],
        "depth": config["depth"],
        "learning_rate": config["learning_rate"],
        "l2_leaf_reg": config["l2_leaf_reg"],
        "random_seed": seed,
        "random_strength": 1.0,
        "bootstrap_type": "Bayesian",
        "bagging_temperature": 1.0,
        "thread_count": 1,
        "cat_features": list(CATEGORICAL_FEATURES),
    }
    for optional in ("max_ctr_complexity", "one_hot_max_size"):
        if optional in config:
            params[optional] = config[optional]
    return params


def build_model(config: dict[str, Any], seed: int) -> CatBoostRegressor:
    params = parameters_for(config, seed)
    model_params = {
        key: value
        for key, value in params.items()
        if key not in ("cat_features",)
    }
    return CatBoostRegressor(
        **model_params,
        verbose=False,
        allow_writing_files=False,
    )


def fit_model(
    config: dict[str, Any],
    frame: pd.DataFrame,
    seed: int,
) -> CatBoostRegressor:
    model = build_model(config, seed)
    model.fit(
        frame.loc[:, list(FEATURE_COLUMNS)],
        frame[TARGET_COLUMN],
        cat_features=list(CATEGORICAL_FEATURES),
        verbose=False,
    )
    return model


def predict_frame(model: CatBoostRegressor, frame: pd.DataFrame) -> np.ndarray:
    return np.asarray(
        model.predict(frame.loc[:, list(FEATURE_COLUMNS)]),
        dtype=float,
    )


def make_validation_split(
    train_pool: pd.DataFrame,
) -> tuple[pd.DataFrame, pd.DataFrame, int, dict[str, Any]]:
    """Find a deterministic group-safe train/validation split.

    Seeds are tried only within the Phase 2 training pool. The test set is not
    involved in this search.
    """
    for seed in range(VALIDATION_SEED_START, VALIDATION_SEED_START + 10):
        train, validation = assign_split(
            train_pool,
            test_fraction=VALIDATION_FRACTION,
            seed=seed,
        )
        summary = split_summary(
            train_pool,
            train,
            validation,
            test_fraction=VALIDATION_FRACTION,
            seed=seed,
        )
        if not summary["missing_categories"]:
            return train, validation, seed, summary

    raise RuntimeError(
        "Could not create a validation split containing every category."
    )


def evaluate_trial(
    config: dict[str, Any],
    train: pd.DataFrame,
    validation: pd.DataFrame,
    seed: int,
) -> dict[str, Any]:
    model = fit_model(config, train, seed=seed)
    predictions = predict_frame(model, validation)
    actual = validation[TARGET_COLUMN].to_numpy(dtype=float)

    return {
        "id": config["id"],
        "config": config,
        "parameters": parameters_for(config, seed),
        "validation": {
            "overall": regression_metrics(actual, predictions),
            "per_category": per_category_metrics(validation, predictions),
        },
    }


def select_best_trial(trials: list[dict[str, Any]]) -> dict[str, Any]:
    """Select by validation MAE, then MAPE. Never uses test metrics."""
    if not trials:
        raise ValueError("No tuning trials were run.")
    return min(
        trials,
        key=lambda trial: (
            trial["validation"]["overall"]["mae"],
            trial["validation"]["overall"]["mape_percent"],
        ),
    )


def decision(
    v1_metrics: dict[str, float],
    candidate_metrics: dict[str, float],
    v1_per_category: dict[str, dict[str, Any]],
    candidate_per_category: dict[str, dict[str, Any]],
) -> dict[str, Any]:
    mae_improvement = (
        (v1_metrics["mae"] - candidate_metrics["mae"])
        / v1_metrics["mae"]
        * 100
    )
    mape_change = (
        (candidate_metrics["mape_percent"] - v1_metrics["mape_percent"])
        / v1_metrics["mape_percent"]
        * 100
    )
    rmse_change = (
        (candidate_metrics["rmse"] - v1_metrics["rmse"])
        / v1_metrics["rmse"]
        * 100
    )

    category_changes = {
        category: round(
            (
                candidate_per_category[category]["mae"]
                - v1_per_category[category]["mae"]
            )
            / v1_per_category[category]["mae"]
            * 100,
            4,
        )
        for category in sorted(v1_per_category)
    }
    worst_category_change = max(category_changes.values())
    save = (
        mae_improvement >= 1.0
        and mape_change <= 1.0
        and worst_category_change <= 10.0
    )

    if save:
        reason = (
            "Candidate meets the improvement rule: final test MAE improves by "
            f"{mae_improvement:.2f}%, MAPE changes by {mape_change:.2f}%, and "
            f"the worst category change is {worst_category_change:.2f}%."
        )
    else:
        reason = (
            "Candidate does not justify replacing v1: final test MAE "
            f"improvement is {mae_improvement:.2f}%, MAPE change is "
            f"{mape_change:.2f}%, and the worst category change is "
            f"{worst_category_change:.2f}%. All three must satisfy the "
            "documented replacement rule."
        )

    return {
        "save_improved_model": save,
        "rule": SELECTION_RULE,
        "mae_improvement_percent": round(mae_improvement, 4),
        "mape_change_percent": round(mape_change, 4),
        "rmse_change_percent": round(rmse_change, 4),
        "category_mae_change_percent": category_changes,
        "worst_category_change_percent": worst_category_change,
        "reason": reason,
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


def load_v1() -> tuple[CatBoostRegressor, Path, dict[str, Any]]:
    metrics_path = REPORTS_DIR / "metrics.json"
    if not metrics_path.is_file():
        raise FileNotFoundError(
            f"Phase 2 metrics not found: {metrics_path}. Run `python train.py` first."
        )
    report = json.loads(metrics_path.read_text(encoding="utf-8"))
    model_path = MODELS_DIR / report["model"]["file"]
    if not model_path.is_file():
        raise FileNotFoundError(f"Phase 2 model not found: {model_path}")
    model, path = load_model(model_path)
    return model, path, report


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Tune CatBoost on validation data and compare with v1."
    )
    parser.add_argument(
        "--dataset",
        type=Path,
        default=DEFAULT_DATASET,
        help="Dataset used to reconstruct the Phase 2 split.",
    )
    args = parser.parse_args(argv)

    try:
        frame, dataset_summary = load_and_validate_dataset(args.dataset)
        train_pool, test = assign_split(
            frame,
            test_fraction=PHASE2_TEST_FRACTION,
            seed=PHASE2_SEED,
        )
        train_frame, validation_frame, validation_seed, validation_summary = (
            make_validation_split(train_pool)
        )
        v1_model, v1_path, v1_report = load_v1()
    except (FileNotFoundError, ValueError, RuntimeError) as exc:
        print(f"Improvement run failed: {exc}", file=sys.stderr)
        return 1

    print(
        f"Phase 2 pool: {len(train_pool)} rows; "
        f"test: {len(test)} rows (untouched during tuning)."
    )
    print(
        f"Validation split: seed={validation_seed}, "
        f"train={len(train_frame)}, validation={len(validation_frame)}."
    )

    trials: list[dict[str, Any]] = []
    for config in trial_configs():
        print(f"  running {config['id']} ...", flush=True)
        trial = evaluate_trial(
            config,
            train_frame,
            validation_frame,
            seed=PHASE2_SEED,
        )
        trials.append(trial)
        overall = trial["validation"]["overall"]
        print(
            f"    validation MAE={overall['mae']:,.2f}, "
            f"RMSE={overall['rmse']:,.2f}, MAPE={overall['mape_percent']:.2f}%",
            flush=True,
        )

    selected = select_best_trial(trials)
    print(f"\nSelected trial: {selected['id']}")

    # The final test set is used only after the selection is frozen.
    candidate_model = fit_model(
        selected["config"],
        train_pool,
        seed=PHASE2_SEED,
    )
    candidate_predictions = predict_frame(candidate_model, test)
    v1_predictions = predict_frame(v1_model, test)
    baseline_predictions, _, _ = median_price_per_kg_baseline(train_pool, test)

    actual = test[TARGET_COLUMN].to_numpy(dtype=float)
    candidate_overall = regression_metrics(actual, candidate_predictions)
    v1_overall = regression_metrics(actual, v1_predictions)
    baseline_overall = regression_metrics(actual, baseline_predictions)
    candidate_per_category = per_category_metrics(test, candidate_predictions)
    v1_per_category = per_category_metrics(test, v1_predictions)
    baseline_per_category = per_category_metrics(test, baseline_predictions)

    verdict = decision(
        v1_overall,
        candidate_overall,
        v1_per_category,
        candidate_per_category,
    )

    comparison: dict[str, Any] = {
        "generated_at_utc": datetime.now(timezone.utc).strftime(
            "%Y-%m-%dT%H:%M:%SZ"
        ),
        "dataset": {
            "filename": dataset_summary["filename"],
            "sha256": dataset_summary["sha256"],
            "provenance": "synthetic",
            "rows_after_deduplication": dataset_summary[
                "rows_after_exact_duplicate_removal"
            ],
        },
        "methodology": {
            "phase2_seed": PHASE2_SEED,
            "phase2_training_pool_rows": int(len(train_pool)),
            "phase2_test_rows": int(len(test)),
            "validation_seed": validation_seed,
            "validation_fraction": VALIDATION_FRACTION,
            "validation_train_rows": int(len(train_frame)),
            "validation_rows": int(len(validation_frame)),
            "validation_counts_by_category": validation_summary[
                "counts_by_category"
            ],
            "test_used_for_selection": False,
            "note": (
                "Hyperparameters were selected only on validation data. The "
                "untouched Phase 2 test set was used once for the final "
                "comparison."
            ),
        },
        "phase2_v1": {
            "model_file": v1_path.name,
            "reported_overall": v1_report["evaluation"]["catboost"]["overall"],
            "recomputed_test_overall": v1_overall,
            "per_category": v1_per_category,
        },
        "validation_search": {
            "trials": trials,
            "selected_trial_id": selected["id"],
            "selected_validation": selected["validation"],
        },
        "final_test": {
            "candidate": {
                "overall": candidate_overall,
                "per_category": candidate_per_category,
            },
            "v1": {
                "overall": v1_overall,
                "per_category": v1_per_category,
            },
            "baseline_median_price_per_kg": {
                "overall": baseline_overall,
                "per_category": baseline_per_category,
            },
        },
        "decision": verdict,
        "saved_model": None,
        "warning": SYNTHETIC_WARNING,
    }

    if verdict["save_improved_model"]:
        MODELS_DIR.mkdir(parents=True, exist_ok=True)
        stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
        model_path = MODELS_DIR / f"catboost_price_{MODEL_VERSION}_{stamp}.cbm"
        candidate_model.save_model(str(model_path))

        profile = build_training_profile(
            train_pool,
            model_file=model_path.name,
            provenance="synthetic",
        )
        save_training_profile(model_path, profile)

        metrics_v2: dict[str, Any] = {
            "model": {
                "version": MODEL_VERSION,
                "file": model_path.name,
                "sha256": sha256_file(model_path),
                "trained_at_utc": datetime.now(timezone.utc).strftime(
                    "%Y-%m-%dT%H:%M:%SZ"
                ),
                "catboost_version": catboost.__version__,
                "parameters": selected["parameters"],
                "feature_schema": {
                    "features": list(FEATURE_COLUMNS),
                    "categorical": list(CATEGORICAL_FEATURES),
                    "numeric": ["age_months", "weight_kg"],
                    "target": TARGET_COLUMN,
                    "target_unit": "PHP",
                },
                "supported_categories": list(SUPPORTED_CATEGORIES),
                "supported_breeds": {
                    category: list(breeds)
                    for category, breeds in SUPPORTED_BREEDS.items()
                },
            },
            "dataset": {
                **dataset_summary,
                "provenance": "synthetic",
            },
            "split": {
                "phase2_seed": PHASE2_SEED,
                "train_rows": int(len(train_pool)),
                "test_rows": int(len(test)),
                "validation_seed": validation_seed,
                "validation_rows_for_selection": int(len(validation_frame)),
                "test_used_for_selection": False,
            },
            "selection": {
                "selected_trial_id": selected["id"],
                "selected_validation": selected["validation"],
                "decision": verdict,
            },
            "evaluation": {
                "catboost": {
                    "overall": candidate_overall,
                    "per_category": candidate_per_category,
                },
                "baseline_median_price_per_kg": {
                    "overall": baseline_overall,
                    "per_category": baseline_per_category,
                },
                "v1_reference": {
                    "model_file": v1_path.name,
                    "overall": v1_overall,
                    "per_category": v1_per_category,
                },
            },
            "training_profile": profile,
            "warning": SYNTHETIC_WARNING,
        }
        metrics_v2_path = REPORTS_DIR / "metrics_v2.json"
        metrics_v2_path.write_text(
            json.dumps(_json_safe(metrics_v2), indent=2, ensure_ascii=False)
            + "\n",
            encoding="utf-8",
        )
        comparison["saved_model"] = {
            "file": model_path.name,
            "metrics_v2": metrics_v2_path.name,
            "training_profile": profile["model_file"],
        }

    REPORTS_DIR.mkdir(parents=True, exist_ok=True)
    comparison_path = REPORTS_DIR / "improvement_comparison.json"
    comparison_path.write_text(
        json.dumps(_json_safe(comparison), indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )

    print("\nFinal untouched-test comparison")
    print(
        f"  v1:        MAE={v1_overall['mae']:,.2f}, "
        f"RMSE={v1_overall['rmse']:,.2f}, "
        f"MAPE={v1_overall['mape_percent']:.2f}%"
    )
    print(
        f"  candidate: MAE={candidate_overall['mae']:,.2f}, "
        f"RMSE={candidate_overall['rmse']:,.2f}, "
        f"MAPE={candidate_overall['mape_percent']:.2f}%"
    )
    print(
        f"  baseline:  MAE={baseline_overall['mae']:,.2f}, "
        f"RMSE={baseline_overall['rmse']:,.2f}, "
        f"MAPE={baseline_overall['mape_percent']:.2f}%"
    )
    print(f"\nDecision: {'SAVE v2' if verdict['save_improved_model'] else 'RETAIN v1'}")
    print(verdict["reason"])
    print(f"Comparison: {comparison_path}")
    if comparison["saved_model"]:
        print(f"Improved model: {MODELS_DIR / comparison['saved_model']['file']}")
    print(f"\n{SYNTHETIC_WARNING}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
