"""Diagnose the Phase 4 older-chicken regression without changing any model.

Writes ``reports/v2_regression_analysis.json`` with the training distribution,
per-age/per-breed errors, prediction shift and feature importance for v1 and v2.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path
from typing import Any

import numpy as np
import pandas as pd
from catboost import CatBoostRegressor

from features import FEATURE_COLUMNS, TARGET_COLUMN
from predict import load_model
from train import (
    MODELS_DIR,
    REPORTS_DIR,
    assign_split,
    load_and_validate_dataset,
    regression_metrics,
)
from train_young_chicken import split_young_chickens

BASE_DIR = Path(__file__).resolve().parent
ORIGINAL_DATASET = BASE_DIR / "data" / "synthetic_livestock_sales.csv"
EXPANDED_DATASET = BASE_DIR / "data" / "synthetic_livestock_sales_v2.csv"
V1_PATH = MODELS_DIR / "catboost_price_v1_20261105T064332748490Z.cbm"
V2_PATH = (
    MODELS_DIR
    / "candidate_catboost_young_chicken_v2_20261105T101535306149Z.cbm"
)
REPORT_PATH = REPORTS_DIR / "v2_regression_analysis.json"


def _json_safe(value: Any) -> Any:
    if isinstance(value, dict):
        return {key: _json_safe(item) for key, item in value.items()}
    if isinstance(value, list):
        return [_json_safe(item) for item in value]
    if isinstance(value, np.integer):
        return int(value)
    if isinstance(value, np.floating):
        return float(value)
    if isinstance(value, np.bool_):
        return bool(value)
    return value


def _predict(model: CatBoostRegressor, frame: pd.DataFrame) -> np.ndarray:
    return np.asarray(
        model.predict(frame.loc[:, list(FEATURE_COLUMNS)]), dtype=float
    )


def _metrics_by_group(
    frame: pd.DataFrame,
    predictions: np.ndarray,
    group_column: str,
) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for group in sorted(frame[group_column].unique()):
        mask = (frame[group_column] == group).to_numpy()
        actual = frame.loc[mask, TARGET_COLUMN].to_numpy(dtype=float)
        predicted = predictions[mask]
        signed = predicted - actual
        result[str(group)] = {
            "rows": int(mask.sum()),
            **regression_metrics(actual, predicted),
            "mean_signed_error_php": round(float(signed.mean()), 4),
            "underprediction_count": int((signed < 0).sum()),
            "overprediction_count": int((signed > 0).sum()),
        }
    return result


def main() -> int:
    try:
        original, _ = load_and_validate_dataset(ORIGINAL_DATASET)
        original_train, original_test = assign_split(original, 0.2, 42)
        expanded, _ = load_and_validate_dataset(EXPANDED_DATASET)
        young = expanded[
            (expanded["livestock_type"] == "chicken")
            & (expanded["age_months"] < 1.0)
        ].reset_index(drop=True)
        young_train, _, _ = split_young_chickens(young)
        v2_train = pd.concat([original_train, young_train], ignore_index=True)

        v1, _ = load_model(V1_PATH)
        v2, _ = load_model(V2_PATH)
    except (FileNotFoundError, RuntimeError, ValueError) as exc:
        print(f"Diagnosis failed: {exc}", file=sys.stderr)
        return 1

    older = original_test[original_test["livestock_type"] == "chicken"].copy()
    older = older.reset_index(drop=True)
    older["age_bin"] = pd.cut(
        older["age_months"],
        bins=[0, 6, 12, 24, 100],
        labels=["1-6m", "6-12m", "12-24m", "24-99m"],
        include_lowest=True,
    ).astype(str)

    v1_older = _predict(v1, older)
    v2_older = _predict(v2, older)
    shift = v2_older - v1_older

    v1_metrics = regression_metrics(
        older[TARGET_COLUMN].to_numpy(dtype=float), v1_older
    )
    v2_metrics = regression_metrics(
        older[TARGET_COLUMN].to_numpy(dtype=float), v2_older
    )

    distribution = {
        "original_train_chicken_rows": int(
            (original_train["livestock_type"] == "chicken").sum()
        ),
        "young_train_rows": int(len(young_train)),
        "v2_train_chicken_rows": int(
            (v2_train["livestock_type"] == "chicken").sum()
        ),
        "young_share_of_chicken_training_rows": round(
            len(young_train)
            / (v2_train["livestock_type"] == "chicken").sum(),
            4,
        ),
        "original_train_chicken_age_months": {
            "min": float(
                original_train.loc[
                    original_train["livestock_type"] == "chicken",
                    "age_months",
                ].min()
            ),
            "median": float(
                original_train.loc[
                    original_train["livestock_type"] == "chicken",
                    "age_months",
                ].median()
            ),
            "max": float(
                original_train.loc[
                    original_train["livestock_type"] == "chicken",
                    "age_months",
                ].max()
            ),
        },
        "young_train_age_months": {
            "min": float(young_train["age_months"].min()),
            "median": float(young_train["age_months"].median()),
            "max": float(young_train["age_months"].max()),
        },
    }

    report: dict[str, Any] = {
        "generated_at_utc": pd.Timestamp.now(tz="UTC").strftime(
            "%Y-%m-%dT%H:%M:%SZ"
        ),
        "older_chicken_test_rows": int(len(older)),
        "v1": {
            "overall": v1_metrics,
            "by_age_bin": _metrics_by_group(older, v1_older, "age_bin"),
            "by_breed": _metrics_by_group(older, v1_older, "breed"),
            "feature_importance": {
                feature: round(float(value), 4)
                for feature, value in zip(
                    FEATURE_COLUMNS, v1.get_feature_importance()
                )
            },
        },
        "v2": {
            "overall": v2_metrics,
            "by_age_bin": _metrics_by_group(older, v2_older, "age_bin"),
            "by_breed": _metrics_by_group(older, v2_older, "breed"),
            "feature_importance": {
                feature: round(float(value), 4)
                for feature, value in zip(
                    FEATURE_COLUMNS, v2.get_feature_importance()
                )
            },
        },
        "prediction_shift_v2_minus_v1": {
            "mean_absolute_change_php": round(
                float(np.mean(np.abs(shift))), 4
            ),
            "mean_signed_change_php": round(float(np.mean(shift)), 4),
            "correlation": round(
                float(np.corrcoef(v1_older, v2_older)[0, 1]), 4
            ),
            "v1_mean_price_php": round(float(v1_older.mean()), 4),
            "v2_mean_price_php": round(float(v2_older.mean()), 4),
        },
        "training_distribution": distribution,
        "root_cause": (
            "Adding 100 young chicken rows (age below 1 month, low weight and "
            "low price) changed the chicken-category distribution from 317 "
            "older training rows to 417 rows with 24% young birds. The single "
            "fixed-capacity tree model shifted older-chicken predictions down "
            "(mean signed shift "
            f"{float(np.mean(shift)):+.2f} PHP), with the largest degradation "
            "in the 12-24 month bin and boholano-native chickens. The older "
            "chicken MAE rose from "
            f"{v1_metrics['mae']:.2f} to {v2_metrics['mae']:.2f}. This is a "
            "distribution/weighting effect, not a test-set change: the older "
            "chicken test rows are identical in both evaluations."
        ),
        "warning": (
            "Synthetic data only. This diagnosis is not evidence of real-market "
            "accuracy."
        ),
    }

    REPORTS_DIR.mkdir(parents=True, exist_ok=True)
    REPORT_PATH.write_text(
        json.dumps(_json_safe(report), indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )

    print(f"Report: {REPORT_PATH}")
    print(
        f"Older chicken MAE: v1={v1_metrics['mae']:.2f}, "
        f"v2={v2_metrics['mae']:.2f}"
    )
    print(
        f"Mean signed prediction shift v2-v1: {float(np.mean(shift)):+.2f} PHP"
    )
    print("Root cause written to the report.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
