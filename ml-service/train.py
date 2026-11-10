"""Train the AgroBenta prototype livestock price model.

The synthetic dataset is for prototype development only. Metrics produced here
do not establish real-market accuracy.

Usage:
    python train.py
    python train.py --dataset data/synthetic_livestock_sales.csv
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import random
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
    NUMERIC_FEATURES,
    SUPPORTED_BREEDS,
    SUPPORTED_CATEGORIES,
    TARGET_COLUMN,
    DatasetValidationError,
    validate_and_normalize_frame,
)
from validation import build_training_profile, save_training_profile

BASE_DIR = Path(__file__).resolve().parent
DEFAULT_DATASET = BASE_DIR / "data" / "synthetic_livestock_sales.csv"
MODELS_DIR = BASE_DIR / "models"
REPORTS_DIR = BASE_DIR / "reports"

MODEL_VERSION = "v1"
DEFAULT_SEED = 42
DEFAULT_TEST_FRACTION = 0.2
DEFAULT_ITERATIONS = 1000
DEFAULT_DEPTH = 6
DEFAULT_LEARNING_RATE = 0.05
DEFAULT_L2_LEAF_REG = 3.0

SYNTHETIC_WARNING = (
    "Synthetic data only. These held-out metrics demonstrate prototype "
    "behaviour, not verified real-market price accuracy."
)


def sha256_file(path: Path) -> str:
    """Return the SHA-256 hash of a file's raw bytes."""
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def infer_provenance(path: Path) -> str:
    """Infer ``synthetic`` from the filename, otherwise ``real``."""
    return "synthetic" if "synthetic" in path.stem.lower() else "real"


def load_and_validate_dataset(path: Path) -> tuple[pd.DataFrame, dict[str, Any]]:
    """Read, validate, normalize and de-duplicate a training CSV.

    Exact duplicates are removed. Repeated feature combinations with different
    prices are retained, and are kept together by :func:`assign_split`.
    """
    path = path.resolve()
    if not path.is_file():
        raise DatasetValidationError(f"Dataset not found: {path}")

    try:
        raw = pd.read_csv(path, encoding="utf-8-sig")
    except pd.errors.EmptyDataError as exc:
        raise DatasetValidationError(f"Dataset is empty: {path}") from exc
    except UnicodeDecodeError as exc:
        raise DatasetValidationError(
            f"Dataset must be UTF-8 encoded: {path}"
        ) from exc

    normalized, ignored_columns = validate_and_normalize_frame(raw)
    rows_loaded = len(normalized)

    deduplicated = normalized.drop_duplicates(ignore_index=True)
    exact_duplicates_removed = rows_loaded - len(deduplicated)

    feature_duplicates = int(
        deduplicated.duplicated(subset=list(FEATURE_COLUMNS)).sum()
    )
    conflicting_groups = 0
    if feature_duplicates:
        target_counts = deduplicated.groupby(
            list(FEATURE_COLUMNS), dropna=False
        )[TARGET_COLUMN].nunique()
        conflicting_groups = int((target_counts > 1).sum())

    category_counts = {
        str(category): int(count)
        for category, count in deduplicated["livestock_type"]
        .value_counts()
        .sort_index()
        .items()
    }

    breed_counts: dict[str, dict[str, int]] = {}
    for category, group in deduplicated.groupby("livestock_type", sort=True):
        breed_counts[str(category)] = {
            str(breed): int(count)
            for breed, count in group["breed"].value_counts().sort_index().items()
        }

    summary: dict[str, Any] = {
        "filename": path.name,
        "relative_path": _relative_to_base(path),
        "sha256": sha256_file(path),
        "rows_loaded": rows_loaded,
        "rows_after_exact_duplicate_removal": int(len(deduplicated)),
        "exact_duplicates_removed": int(exact_duplicates_removed),
        "feature_duplicate_rows": feature_duplicates,
        "feature_groups_with_conflicting_prices": conflicting_groups,
        "ignored_columns": ignored_columns,
        "counts_by_category": category_counts,
        "counts_by_breed": breed_counts,
    }

    return deduplicated, summary


def _relative_to_base(path: Path) -> str:
    try:
        return path.relative_to(BASE_DIR).as_posix()
    except ValueError:
        return path.as_posix()


def feature_group_keys(frame: pd.DataFrame) -> pd.Series:
    """Return one tuple key per row from the five model features.

    Every row sharing a key is an identical feature combination. The splitter
    keeps all such rows together so no observation can appear in both splits.
    """
    keys = [
        tuple(row)
        for row in frame.loc[:, list(FEATURE_COLUMNS)].itertuples(
            index=False, name=None
        )
    ]
    return pd.Series(keys, index=frame.index, name="_feature_key")


def assign_split(
    frame: pd.DataFrame,
    test_fraction: float = DEFAULT_TEST_FRACTION,
    seed: int = DEFAULT_SEED,
) -> tuple[pd.DataFrame, pd.DataFrame]:
    """Create a reproducible, leakage-safe 80/20 split.

    Feature-equivalent rows are grouped. Groups are assigned per livestock
    breed, shuffled with a fixed seed, until the breed's test share is reached.
    That approximates breed/category stratification while guaranteeing that no
    feature group crosses the split boundary.
    """
    if not 0 < test_fraction < 1:
        raise ValueError("test_fraction must be between 0 and 1.")

    work = frame.copy()
    work["_feature_key"] = feature_group_keys(work)
    rng = random.Random(seed)
    test_keys: set[tuple[Any, ...]] = set()

    breed_pairs = sorted(
        {
            (str(category), str(breed))
            for category, breed in work[["livestock_type", "breed"]].itertuples(
                index=False, name=None
            )
        }
    )

    for category, breed in breed_pairs:
        breed_rows = work[
            (work["livestock_type"] == category) & (work["breed"] == breed)
        ]
        groups = list(breed_rows.groupby("_feature_key", sort=False))
        groups.sort(key=lambda item: repr(item[0]))
        rng.shuffle(groups)

        target_rows = max(1, round(len(breed_rows) * test_fraction))
        selected_rows = 0

        for index, (key, group) in enumerate(groups):
            if selected_rows >= target_rows:
                break
            # Keep at least one group for training. A breed represented by a
            # single feature combination cannot be split without leaking it.
            if index == len(groups) - 1:
                break
            test_keys.add(key)
            selected_rows += len(group)

    in_test = work["_feature_key"].isin(test_keys)
    train = (
        work.loc[~in_test]
        .drop(columns="_feature_key")
        .reset_index(drop=True)
    )
    test = (
        work.loc[in_test]
        .drop(columns="_feature_key")
        .reset_index(drop=True)
    )

    train_keys = set(feature_group_keys(train))
    test_keys_after = set(feature_group_keys(test))
    overlap = train_keys & test_keys_after
    if overlap:
        raise RuntimeError(
            f"Leakage-safe split failed: {len(overlap)} feature group(s) in both splits."
        )
    if train.empty or test.empty:
        raise RuntimeError("Leakage-safe split produced an empty train or test set.")

    return train, test


def split_summary(
    frame: pd.DataFrame,
    train: pd.DataFrame,
    test: pd.DataFrame,
    test_fraction: float,
    seed: int,
) -> dict[str, Any]:
    """Describe the split, including per-category representation."""
    categories = sorted(str(value) for value in frame["livestock_type"].unique())
    counts_by_category = {
        category: {
            "train": int((train["livestock_type"] == category).sum()),
            "test": int((test["livestock_type"] == category).sum()),
        }
        for category in categories
    }
    held_out_categories = sorted(
        str(value) for value in test["livestock_type"].unique()
    )
    missing_categories = [
        category for category in categories if category not in held_out_categories
    ]

    return {
        "seed": seed,
        "test_fraction_requested": test_fraction,
        "test_fraction_actual": round(len(test) / len(frame), 4),
        "train_rows": int(len(train)),
        "test_rows": int(len(test)),
        "counts_by_category": counts_by_category,
        "held_out_categories": held_out_categories,
        "missing_categories": missing_categories,
        "feature_groups_in_both_splits": len(
            set(feature_group_keys(train)) & set(feature_group_keys(test))
        ),
    }


def regression_metrics(y_true: Any, y_pred: Any) -> dict[str, float]:
    """Return MAE, RMSE and MAPE (as a percentage) in PHP."""
    actual = np.asarray(y_true, dtype=float)
    predicted = np.asarray(y_pred, dtype=float)

    if actual.size == 0 or predicted.size == 0:
        raise ValueError("Metrics require at least one prediction.")
    if actual.shape != predicted.shape:
        raise ValueError("Actual and predicted arrays must have the same shape.")
    if np.any(actual == 0):
        raise ValueError("MAPE is undefined when an actual price is zero.")

    absolute_error = np.abs(actual - predicted)
    squared_error = np.square(actual - predicted)
    percentage_error = np.abs((actual - predicted) / actual)

    return {
        "mae": round(float(np.mean(absolute_error)), 4),
        "rmse": round(float(np.sqrt(np.mean(squared_error))), 4),
        "mape_percent": round(float(np.mean(percentage_error) * 100), 4),
    }


def per_category_metrics(
    frame: pd.DataFrame,
    predictions: np.ndarray,
) -> dict[str, dict[str, Any]]:
    """Evaluate one category at a time on held-out rows."""
    result: dict[str, dict[str, Any]] = {}

    for category in sorted(str(value) for value in frame["livestock_type"].unique()):
        mask = (frame["livestock_type"] == category).to_numpy()
        if not mask.any():
            continue
        metrics = regression_metrics(
            frame.loc[mask, TARGET_COLUMN].to_numpy(),
            predictions[mask],
        )
        result[category] = {"n": int(mask.sum()), **metrics}

    return result


def median_price_per_kg_baseline(
    train: pd.DataFrame,
    test: pd.DataFrame,
) -> tuple[np.ndarray, dict[str, float], float]:
    """Return a training-only median price-per-kg baseline.

    The category rate is the median of ``actual_sale_price / weight_kg`` on the
    training rows. The global training rate is the fallback for an unseen
    category. The baseline never reads the test target.
    """
    train_price_per_kg = train[TARGET_COLUMN] / train["weight_kg"]
    global_rate = float(train_price_per_kg.median())
    rates = {
        str(category): float((group[TARGET_COLUMN] / group["weight_kg"]).median())
        for category, group in train.groupby("livestock_type", sort=True)
    }

    category_rates = test["livestock_type"].map(rates).astype(float)
    if category_rates.isna().any():
        category_rates = category_rates.fillna(global_rate)

    predictions = (category_rates * test["weight_kg"]).to_numpy(dtype=float)
    return predictions, rates, global_rate


def build_model(
    seed: int,
    iterations: int,
    depth: int,
    learning_rate: float,
    l2_leaf_reg: float,
    thread_count: int = 1,
) -> CatBoostRegressor:
    """Build the one CatBoost regressor used for every category.

    ``thread_count`` is an execution setting, not a model-quality setting. The
    default stays 1 for the original reproducible training path; tuning may use
    more threads to keep a controlled search practical.
    """
    return CatBoostRegressor(
        # Direct-price MAE avoids letting the high-value cattle/carabao rows
        # dominate the objective and underfit low-value chicken rows.
        loss_function="MAE",
        eval_metric="MAE",
        iterations=iterations,
        depth=depth,
        learning_rate=learning_rate,
        l2_leaf_reg=l2_leaf_reg,
        random_seed=seed,
        random_strength=1.0,
        bootstrap_type="Bayesian",
        bagging_temperature=1.0,
        thread_count=thread_count,
        verbose=False,
        allow_writing_files=False,
    )


def model_parameters(
    seed: int,
    iterations: int,
    depth: int,
    learning_rate: float,
    l2_leaf_reg: float,
    thread_count: int = 1,
) -> dict[str, Any]:
    """The parameter record written to metrics.json."""
    return {
        "loss_function": "MAE",
        "eval_metric": "MAE",
        "iterations": iterations,
        "depth": depth,
        "learning_rate": learning_rate,
        "l2_leaf_reg": l2_leaf_reg,
        "random_seed": seed,
        "random_strength": 1.0,
        "bootstrap_type": "Bayesian",
        "bagging_temperature": 1.0,
        "thread_count": thread_count,
        "cat_features": list(CATEGORICAL_FEATURES),
    }


def _unique_model_path(version: str) -> Path:
    MODELS_DIR.mkdir(parents=True, exist_ok=True)
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
    path = MODELS_DIR / f"catboost_price_{version}_{stamp}.cbm"
    suffix = 1
    while path.exists():
        path = MODELS_DIR / f"catboost_price_{version}_{stamp}_{suffix}.cbm"
        suffix += 1
    return path


def train(
    dataset_path: Path = DEFAULT_DATASET,
    provenance: str | None = None,
    seed: int = DEFAULT_SEED,
    test_fraction: float = DEFAULT_TEST_FRACTION,
    iterations: int = DEFAULT_ITERATIONS,
    depth: int = DEFAULT_DEPTH,
    learning_rate: float = DEFAULT_LEARNING_RATE,
    l2_leaf_reg: float = DEFAULT_L2_LEAF_REG,
) -> tuple[Path, Path, dict[str, Any]]:
    """Train, evaluate and persist one model and its report."""
    frame, dataset_summary = load_and_validate_dataset(dataset_path)

    train_frame, test_frame = assign_split(
        frame, test_fraction=test_fraction, seed=seed
    )
    split = split_summary(
        frame,
        train_frame,
        test_frame,
        test_fraction=test_fraction,
        seed=seed,
    )

    parameters = model_parameters(
        seed=seed,
        iterations=iterations,
        depth=depth,
        learning_rate=learning_rate,
        l2_leaf_reg=l2_leaf_reg,
    )
    model = build_model(
        seed=seed,
        iterations=iterations,
        depth=depth,
        learning_rate=learning_rate,
        l2_leaf_reg=l2_leaf_reg,
    )
    model.fit(
        train_frame.loc[:, list(FEATURE_COLUMNS)],
        train_frame[TARGET_COLUMN],
        cat_features=list(CATEGORICAL_FEATURES),
        verbose=False,
    )

    predictions = np.asarray(
        model.predict(test_frame.loc[:, list(FEATURE_COLUMNS)]),
        dtype=float,
    )
    baseline_predictions, baseline_rates, baseline_global_rate = (
        median_price_per_kg_baseline(train_frame, test_frame)
    )

    evaluation = {
        "catboost": {
            "overall": regression_metrics(
                test_frame[TARGET_COLUMN].to_numpy(), predictions
            ),
            "per_category": per_category_metrics(test_frame, predictions),
        },
        "baseline_median_price_per_kg": {
            "overall": regression_metrics(
                test_frame[TARGET_COLUMN].to_numpy(), baseline_predictions
            ),
            "per_category": per_category_metrics(
                test_frame, baseline_predictions
            ),
            "training_category_rates_php_per_kg": {
                category: round(rate, 4)
                for category, rate in baseline_rates.items()
            },
            "training_global_rate_php_per_kg": round(baseline_global_rate, 4),
        },
    }

    dataset_provenance = provenance or infer_provenance(dataset_path)
    model_path = _unique_model_path(MODEL_VERSION)
    model.save_model(str(model_path))
    training_profile = build_training_profile(
        train_frame,
        model_file=model_path.name,
        provenance=dataset_provenance,
    )
    save_training_profile(model_path, training_profile)

    trained_at = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    report: dict[str, Any] = {
        "model": {
            "version": MODEL_VERSION,
            "file": model_path.name,
            "sha256": sha256_file(model_path),
            "trained_at_utc": trained_at,
            "catboost_version": catboost.__version__,
            "parameters": parameters,
            "feature_schema": {
                "features": list(FEATURE_COLUMNS),
                "categorical": list(CATEGORICAL_FEATURES),
                "numeric": list(NUMERIC_FEATURES),
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
            "provenance": dataset_provenance,
        },
        "split": split,
        "evaluation": evaluation,
        "training_profile": training_profile,
        "warning": SYNTHETIC_WARNING,
    }

    REPORTS_DIR.mkdir(parents=True, exist_ok=True)
    report_path = REPORTS_DIR / "metrics.json"
    report_path.write_text(
        json.dumps(report, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )

    return model_path, report_path, report


def _print_report(model_path: Path, report_path: Path, report: dict[str, Any]) -> None:
    dataset = report["dataset"]
    split = report["split"]
    catboost_metrics = report["evaluation"]["catboost"]
    baseline_metrics = report["evaluation"]["baseline_median_price_per_kg"]

    print(f"Model:  {model_path}")
    print(f"Report: {report_path}")
    print(
        "Dataset: "
        f"{dataset['filename']} ({dataset['provenance']}), "
        f"{dataset['rows_loaded']} loaded, "
        f"{dataset['rows_after_exact_duplicate_removal']} after deduplication"
    )
    print(
        "Split:   "
        f"train={split['train_rows']}, test={split['test_rows']} "
        f"({split['test_fraction_actual']:.1%}); "
        f"held-out categories={', '.join(split['held_out_categories'])}"
    )
    if split["missing_categories"]:
        print(
            "WARNING: held-out split is missing categories: "
            + ", ".join(split["missing_categories"])
        )

    headers = ("model", "MAE (PHP)", "RMSE (PHP)", "MAPE (%)")
    print("\nHeld-out metrics")
    print(f"{headers[0]:<34}{headers[1]:>14}{headers[2]:>14}{headers[3]:>12}")
    for label, metrics in (
        ("CatBoost", catboost_metrics["overall"]),
        ("Median price/kg baseline", baseline_metrics["overall"]),
    ):
        print(
            f"{label:<34}{metrics['mae']:>14,.2f}"
            f"{metrics['rmse']:>14,.2f}{metrics['mape_percent']:>12,.2f}"
        )

    print("\nPer-category MAE (PHP)")
    categories = sorted(catboost_metrics["per_category"])
    print(
        f"{'category':<12}{'n':>6}{'CatBoost':>16}{'baseline':>16}"
    )
    for category in categories:
        catboost_mae = catboost_metrics["per_category"][category]["mae"]
        baseline_mae = baseline_metrics["per_category"][category]["mae"]
        n = catboost_metrics["per_category"][category]["n"]
        print(f"{category:<12}{n:>6}{catboost_mae:>16,.2f}{baseline_mae:>16,.2f}")

    print(f"\n{SYNTHETIC_WARNING}")


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Train the AgroBenta prototype livestock price model."
    )
    parser.add_argument(
        "--dataset",
        type=Path,
        default=DEFAULT_DATASET,
        help="Training CSV (default: data/synthetic_livestock_sales.csv).",
    )
    parser.add_argument(
        "--provenance",
        choices=("synthetic", "real"),
        default=None,
        help="Dataset provenance label. Defaults to inferring from the filename.",
    )
    parser.add_argument("--seed", type=int, default=DEFAULT_SEED)
    parser.add_argument(
        "--test-fraction", type=float, default=DEFAULT_TEST_FRACTION
    )
    parser.add_argument("--iterations", type=int, default=DEFAULT_ITERATIONS)
    parser.add_argument("--depth", type=int, default=DEFAULT_DEPTH)
    parser.add_argument(
        "--learning-rate", type=float, default=DEFAULT_LEARNING_RATE
    )
    parser.add_argument(
        "--l2-leaf-reg", type=float, default=DEFAULT_L2_LEAF_REG
    )

    args = parser.parse_args(argv)
    if not 0 < args.test_fraction < 1:
        parser.error("--test-fraction must be between 0 and 1")
    if args.iterations <= 0:
        parser.error("--iterations must be greater than 0")
    if not 1 <= args.depth <= 16:
        parser.error("--depth must be between 1 and 16")
    if args.learning_rate <= 0:
        parser.error("--learning-rate must be greater than 0")
    if args.l2_leaf_reg <= 0:
        parser.error("--l2-leaf-reg must be greater than 0")
    return args


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)

    try:
        model_path, report_path, report = train(
            dataset_path=args.dataset,
            provenance=args.provenance,
            seed=args.seed,
            test_fraction=args.test_fraction,
            iterations=args.iterations,
            depth=args.depth,
            learning_rate=args.learning_rate,
            l2_leaf_reg=args.l2_leaf_reg,
        )
    except (DatasetValidationError, FileNotFoundError, ValueError) as exc:
        print(f"Training failed: {exc}")
        return 1

    _print_report(model_path, report_path, report)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
