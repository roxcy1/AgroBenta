"""Finalize the targeted v3 candidate from the completed validation search.

This reuses ``reports/targeted_improvement_v3.json`` (10 completed trials),
runs only the one additional validation configuration, selects with a stricter
young-chicken validation margin, and evaluates the selected model once on the
untouched original and young-chicken test sets.

Existing reports and models are not overwritten.
"""

from __future__ import annotations

import json
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import numpy as np
import pandas as pd

from features import FEATURE_COLUMNS, SUPPORTED_BREEDS, TARGET_COLUMN
from predict import load_model, predict
from train import (
    DEFAULT_DEPTH,
    DEFAULT_ITERATIONS,
    DEFAULT_L2_LEAF_REG,
    DEFAULT_LEARNING_RATE,
    MODELS_DIR,
    REPORTS_DIR,
    SYNTHETIC_WARNING,
    assign_split,
    load_and_validate_dataset,
    median_price_per_kg_baseline,
    regression_metrics,
    sha256_file,
)
from train_young_chicken import split_young_chickens
from tune_targeted_v3 import (
    CANDIDATE_PREFIX,
    CANDIDATE_VERSION,
    V1_OLDER_MAE,
    _age_consistent_predictions,
    _controlled_predictions,
    _invalid_inputs,
    _is_older_chicken,
    _is_young_chicken,
    _json_safe,
    _ood_examples,
    acceptance,
    evaluate_validation,
    find_validation_split,
    fit_trial,
)
from validation import build_training_profile, save_training_profile

BASE_DIR = Path(__file__).resolve().parent
ORIGINAL_DATASET = BASE_DIR / "data" / "synthetic_livestock_sales.csv"
EXPANDED_DATASET = BASE_DIR / "data" / "synthetic_livestock_sales_v2.csv"
PREVIOUS_REPORT = REPORTS_DIR / "targeted_improvement_v3.json"
V1_REPORT = REPORTS_DIR / "metrics.json"
V2_REPORT = REPORTS_DIR / "young_chicken_training_v2.json"
REPORT_PATH = REPORTS_DIR / "targeted_improvement_v3_final.json"
VALIDATION_REPORT_PATH = (
    REPORTS_DIR / "targeted_prediction_validation_v3_final.json"
)

FINAL_TRIAL = {
    "id": "older_2.0_young_1.05",
    "weights": "older_2.0_young_1.05",
    "sample": "full",
    "iterations": DEFAULT_ITERATIONS,
    "depth": DEFAULT_DEPTH,
    "learning_rate": DEFAULT_LEARNING_RATE,
    "l2_leaf_reg": DEFAULT_L2_LEAF_REG,
}


def _metrics(frame: pd.DataFrame, predictions: np.ndarray) -> dict[str, Any]:
    return regression_metrics(
        frame[TARGET_COLUMN].to_numpy(dtype=float), predictions
    )


def _comparison(
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


def select_final(
    trials: list[dict[str, Any]],
    reference: dict[str, Any],
) -> dict[str, Any]:
    """Select the lowest older-chicken MAE with a stricter young margin."""
    ref = reference["validation"]
    eligible: list[dict[str, Any]] = []

    for trial in trials:
        if trial["id"] == reference["id"]:
            continue
        metrics = trial["validation"]
        older_ok = metrics["older_chicken"]["mae"] <= V1_OLDER_MAE
        # Require a 10% validation margin better than the v2 reference, not
        # merely within 10% above it. This protects the young test set, whose
        # earlier candidate had a thin margin.
        young_ok = (
            metrics["young_chicken"]["mae"]
            <= ref["young_chicken"]["mae"] * 0.90
        )
        overall_ok = metrics["overall"]["mae"] <= ref["overall"]["mae"] * 1.02
        category_ok = all(
            metrics["per_category"][category]["mae"]
            <= ref["per_category"][category]["mae"] * 1.05
            for category in ref["per_category"]
        )
        if older_ok and young_ok and overall_ok and category_ok:
            eligible.append(trial)

    candidates = eligible or [
        trial for trial in trials if trial["id"] != reference["id"]
    ]
    selected = min(
        candidates,
        key=lambda trial: (
            trial["validation"]["older_chicken"]["mae"],
            trial["validation"]["young_chicken"]["mae"],
        ),
    )
    return {
        "selected_trial_id": selected["id"],
        "selection_eligible": bool(eligible),
        "eligible_trial_ids": [trial["id"] for trial in eligible],
        "rule": (
            "Final selection requires older-chicken validation MAE <= 48.49, "
            "young-chicken validation MAE at least 10% below the v2 reference, "
            "overall validation MAE within 2%, and no category more than 5% "
            "worse. This is a validation-only safety margin; the held-out "
            "tests are used once after selection."
        ),
    }


def main() -> int:
    try:
        previous = json.loads(PREVIOUS_REPORT.read_text(encoding="utf-8"))
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
        v2, _ = load_model(MODELS_DIR / v2_report["candidate"]["file"])
    except (FileNotFoundError, RuntimeError, ValueError) as exc:
        print(f"Finalization failed: {exc}", file=sys.stderr)
        return 1

    print("Reusing completed validation trials from the previous report.")
    trials = list(previous["validation"]["trials"])
    if any(trial["id"] == FINAL_TRIAL["id"] for trial in trials):
        final_trial = next(
            trial for trial in trials if trial["id"] == FINAL_TRIAL["id"]
        )
    else:
        print(f"Running only the new validation trial: {FINAL_TRIAL['id']}")
        model = fit_trial(FINAL_TRIAL, validation_train)
        final_trial = {
            "id": FINAL_TRIAL["id"],
            "config": FINAL_TRIAL,
            "validation": evaluate_validation(model, validation),
        }
        trials.append(final_trial)

    reference = next(
        trial for trial in trials if trial["id"] == "v2_reference"
    )
    selection = select_final(trials, reference)
    selected = next(
        trial for trial in trials if trial["id"] == selection["selected_trial_id"]
    )
    print(f"Selected trial: {selected['id']}")
    print(json.dumps(selection, indent=2))

    # Final refit on the full Phase 4 training pool; held-out sets are evaluated
    # only after the selection is frozen.
    final_model = fit_trial(selected["config"], v2_train)
    candidate_original = np.asarray(
        final_model.predict(original_test.loc[:, list(FEATURE_COLUMNS)]),
        dtype=float,
    )
    candidate_young = np.asarray(
        final_model.predict(young_test.loc[:, list(FEATURE_COLUMNS)]),
        dtype=float,
    )
    older_test = original_test[
        original_test["livestock_type"] == "chicken"
    ].reset_index(drop=True)
    candidate_older = np.asarray(
        final_model.predict(older_test.loc[:, list(FEATURE_COLUMNS)]),
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
    v1_older = np.asarray(
        v1.predict(older_test.loc[:, list(FEATURE_COLUMNS)]), dtype=float
    )
    v2_older = np.asarray(
        v2.predict(older_test.loc[:, list(FEATURE_COLUMNS)]), dtype=float
    )

    original_baseline, _, _ = median_price_per_kg_baseline(
        original_train, original_test
    )
    young_baseline, _, _ = median_price_per_kg_baseline(
        v2_train, young_test
    )
    older_baseline, _, _ = median_price_per_kg_baseline(
        original_train, older_test
    )

    original_comparison = _comparison(
        original_test,
        candidate_original,
        v1_original,
        v2_original,
        original_baseline,
    )
    original_comparison["by_category"] = {
        category: _comparison(
            original_test.loc[
                (original_test["livestock_type"] == category)
            ].reset_index(drop=True),
            candidate_original[
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
    young_comparison = _comparison(
        young_test,
        candidate_young,
        v1_young,
        v2_young,
        young_baseline,
    )
    older_comparison = _comparison(
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

    model_path: Path | None = None
    reload_ok = False
    reload_price = None
    profile = build_training_profile(
        v2_train,
        model_file=f"{CANDIDATE_PREFIX}.cbm",
        provenance="synthetic",
    )
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
        reloaded = predict(
            livestock_type="chicken",
            breed="broiler",
            sex="male",
            age_months=10 / 30.4375,
            weight_kg=0.5,
            model=loaded,
            model_path=loaded_path,
        )
        reload_ok = reloaded.price > 0
        reload_price = round(reloaded.price, 2)

    controlled = _controlled_predictions(
        {"candidate": final_model, "v1": v1, "v2": v2}
    )
    age_consistent = _age_consistent_predictions(
        {"candidate": final_model, "v1": v1, "v2": v2}
    )
    invalid_inputs = _invalid_inputs()
    ood = _ood_examples(profile)
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
        "reused_validation_report": PREVIOUS_REPORT.name,
        "previous_selection": previous["validation"]["selection"],
        "previous_acceptance": previous["acceptance"],
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
            "trials": trials,
            "selection": selection,
            "new_trial": FINAL_TRIAL["id"],
            "test_used_for_selection": False,
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
                    "thread_count": 4,
                },
                "sidecar": model_path.with_suffix(".metadata.json").name,
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

    print("\nFinal held-out comparison")
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
    print(f"Report: {REPORT_PATH}")
    print(f"Validation report: {VALIDATION_REPORT_PATH}")
    if model_path is not None:
        print(f"Candidate saved: {model_path}")
    else:
        print("No candidate model saved (acceptance failed).")
    print(f"\n{SYNTHETIC_WARNING}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
