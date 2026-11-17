"""Compare a candidate's original and revised safety profiles.

This script never trains, registers or activates a model. It evaluates two
safety profiles against the same frozen test split and a fixed probe list, then
writes a timestamped report.

Run from the ml-service directory::

    python evaluate_safety.py --version v5
"""

from __future__ import annotations

import argparse
import json
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Mapping

from predict import predict
from model_registry import load_verified_model
from train import MODELS_DIR, REPORTS_DIR, load_and_validate_dataset, sha256_file
from train_candidate import AGE_BANDS, MODEL_VERSION, split_frames
from validation import assess_safety

BASE_DIR = Path(__file__).resolve().parent
DATASET_PATH = BASE_DIR / "data" / "livestock_sales_v5_synthetic.csv"

BREED_ONLY_CODES = {"outside_typical_breed_age", "outside_typical_breed_weight"}

PROBES: tuple[tuple[str, str, str, str, float, float, str], ...] = (
    # name, category, breed, sex, age, weight, expectation
    ("cattle young 3mo/70kg", "cattle", "brahman", "male", 3, 70, "priced"),
    ("cattle growing 12mo/160kg", "cattle", "brahman", "male", 12, 160, "priced"),
    ("cattle mature 48mo/320kg", "cattle", "brahman", "male", 48, 320, "priced"),
    ("cattle older 180mo/350kg", "cattle", "brahman", "female", 180, 350, "priced"),
    ("carabao young 2mo/60kg", "carabao", "murrah", "male", 2, 60, "priced"),
    ("carabao growing 12mo/150kg", "carabao", "murrah", "male", 12, 150, "priced"),
    ("carabao mature 60mo/380kg", "carabao", "murrah", "male", 60, 380, "priced"),
    ("carabao older 120mo/400kg", "carabao", "murrah", "female", 120, 400, "priced"),
    ("goat young 2mo/12kg", "goat", "boer", "female", 2, 12, "priced"),
    ("goat growing 9mo/30kg", "goat", "boer", "female", 9, 30, "priced"),
    ("goat mature 36mo/60kg", "goat", "boer", "female", 36, 60, "priced"),
    ("goat older 120mo/60kg", "goat", "boer", "female", 120, 60, "priced"),
    ("swine young 1mo/11kg", "swine", "landrace", "female", 1, 11, "priced"),
    ("swine growing 5mo/60kg", "swine", "landrace", "female", 5, 60, "priced"),
    ("swine mature 24mo/160kg", "swine", "landrace", "female", 24, 160, "priced"),
    ("swine older 60mo/120kg", "swine", "landrace", "female", 60, 120, "priced"),
    ("chicken young 1mo/0.5kg", "chicken", "broiler", "male", 1, 0.5, "priced"),
    ("chicken growing 3mo/1.8kg", "chicken", "broiler", "male", 3, 1.8, "priced"),
    ("chicken mature 12mo/2.5kg", "chicken", "layer", "female", 12, 2.5, "priced"),
    (
        "chicken older 36mo/3.5kg",
        "chicken",
        "boholano_native_chicken",
        "female",
        36,
        3.5,
        "priced",
    ),
    ("cattle approved min 50kg", "cattle", "brahman", "male", 2, 50, "priced"),
    ("cattle approved max 400kg", "cattle", "brahman", "male", 48, 400, "priced"),
    ("carabao approved min 50kg", "carabao", "murrah", "male", 2, 50, "priced"),
    ("carabao approved max 450kg", "carabao", "murrah", "male", 60, 450, "priced"),
    ("goat approved min 10kg", "goat", "boer", "female", 2, 10, "priced"),
    ("goat approved max 80kg", "goat", "boer", "male", 36, 80, "priced"),
    ("swine approved min 10kg", "swine", "landrace", "female", 1, 10, "priced"),
    ("swine approved max 200kg", "swine", "landrace", "male", 24, 200, "priced"),
    ("chicken approved min 0.3kg", "chicken", "broiler", "male", 1, 0.3, "priced"),
    (
        "chicken approved max 10kg (unsupported)",
        "chicken",
        "broiler",
        "male",
        6,
        10,
        "withheld",
    ),
    ("impossible swine 1mo/23kg", "swine", "landrace", "female", 1, 23, "withheld"),
    ("impossible swine 2mo/60kg", "swine", "landrace", "female", 2, 60, "withheld"),
    ("impossible swine 3mo/60kg", "swine", "landrace", "female", 3, 60, "withheld"),
    ("plausible swine 3mo/45kg", "swine", "landrace", "female", 3, 45, "priced"),
    ("impossible cattle 2mo/350kg", "cattle", "brahman", "male", 2, 350, "withheld"),
    ("impossible goat 2mo/75kg", "goat", "boer", "female", 2, 75, "withheld"),
    ("impossible carabao 3mo/400kg", "carabao", "murrah", "male", 3, 400, "withheld"),
    ("impossible chicken 2mo/9kg", "chicken", "broiler", "male", 2, 9, "withheld"),
    (
        "impossible cattle 215mo/50kg",
        "cattle",
        "philippine_native_cattle",
        "male",
        215,
        50,
        "withheld",
    ),
)


def _age_band(age: float) -> str:
    for label, low, high in AGE_BANDS:
        if age >= low and (high is None or age < high):
            return label
    return AGE_BANDS[-1][0]


def _assess_rows(frame, profile) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
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
        assessment = assess_safety(values, profile)
        rows.append(
            {
                "category": row[0],
                "age_band": _age_band(float(row[3])),
                "status": assessment.status,
                "reason_codes": list(assessment.reason_codes),
                "age_months": float(row[3]),
                "weight_kg": float(row[4]),
            }
        )
    return rows


def _summarize(rows: list[dict[str, Any]]) -> dict[str, Any]:
    total = len(rows)
    overall = Counter(row["status"] for row in rows)

    def grouped(key: str) -> dict[str, Any]:
        result: dict[str, Any] = {}
        for name in sorted({row[key] for row in rows}):
            subset = [row for row in rows if row[key] == name]
            counts = Counter(row["status"] for row in subset)
            result[name] = {
                "rows": len(subset),
                "ok": counts["ok"],
                "warning": counts["warning"],
                "withheld": counts["withheld"],
                "ok_percent": round(100 * counts["ok"] / len(subset), 2),
                "warning_percent": round(
                    100 * counts["warning"] / len(subset), 2
                ),
                "withheld_percent": round(
                    100 * counts["withheld"] / len(subset), 2
                ),
            }
        return result

    breed_only = [
        row
        for row in rows
        if row["status"] == "warning"
        and set(row["reason_codes"])
        and set(row["reason_codes"]).issubset(BREED_ONLY_CODES)
    ]
    return {
        "rows": total,
        "status_counts": {
            "ok": overall["ok"],
            "warning": overall["warning"],
            "withheld": overall["withheld"],
        },
        "status_percent": {
            "ok": round(100 * overall["ok"] / total, 2),
            "warning": round(100 * overall["warning"] / total, 2),
            "withheld": round(100 * overall["withheld"] / total, 2),
        },
        "per_category": grouped("category"),
        "per_age_group": grouped("age_band"),
        "reason_code_counts": dict(
            sorted(Counter(code for row in rows for code in row["reason_codes"]).items())
        ),
        "breed_only_warnings": len(breed_only),
        "withheld_rows": [
            {
                "category": row["category"],
                "age_months": row["age_months"],
                "weight_kg": row["weight_kg"],
                "reason_codes": row["reason_codes"],
            }
            for row in rows
            if row["status"] == "withheld"
        ],
    }


def _run_probe(
    model,
    entry: Mapping[str, Any],
    safety: Mapping[str, Any],
    probe: tuple[str, str, str, str, float, float, str],
) -> dict[str, Any]:
    name, category, breed, sex, age, weight, expectation = probe
    result = predict(
        category,
        breed,
        sex,
        age,
        weight,
        model=model,
        model_entry=entry,
        safety_profile=safety,
    )
    passed = (
        result.status != "withheld"
        if expectation == "priced"
        else result.status == "withheld"
    )
    return {
        "probe": name,
        "expected": expectation,
        "status": result.status,
        "price_php": round(result.price, 2) if result.price else None,
        "reason_codes": list(result.reason_codes),
        "passed": passed,
    }


def evaluate(
    *,
    version: str = MODEL_VERSION,
    model_path: Path | None = None,
    safety_path: Path | None = None,
    compare_path: Path | None = None,
    dataset_path: Path = DATASET_PATH,
    split_manifest_path: Path | None = None,
    report_path: Path | None = None,
) -> tuple[Path, dict[str, Any]]:
    models = sorted(
        MODELS_DIR.glob(f"candidate_catboost_{version}_*.cbm"),
        key=lambda path: (path.stat().st_mtime, path.name),
        reverse=True,
    )
    if model_path is None:
        if not models:
            raise FileNotFoundError(
                f"No candidate_catboost_{version}_*.cbm model found."
            )
        model_path = models[0]

    safety_path = safety_path or model_path.with_suffix(".safety_v2.json")
    if not safety_path.is_file():
        raise FileNotFoundError(f"Revised safety profile not found: {safety_path}")
    compare_path = compare_path or model_path.with_suffix(".safety.json")
    if not compare_path.is_file():
        raise FileNotFoundError(f"Original safety profile not found: {compare_path}")

    manifests = sorted(
        REPORTS_DIR.glob(f"{version}_split_manifest_*.json"),
        key=lambda path: (path.stat().st_mtime, path.name),
        reverse=True,
    )
    if split_manifest_path is None:
        if not manifests:
            raise FileNotFoundError(
                f"No {version}_split_manifest_*.json found."
            )
        split_manifest_path = manifests[0]
    split_manifest = json.loads(split_manifest_path.read_text(encoding="utf-8"))

    frame, dataset_summary = load_and_validate_dataset(dataset_path)
    if split_manifest.get("dataset_sha256") not in (
        None,
        dataset_summary["sha256"],
    ):
        raise ValueError("Dataset SHA-256 does not match the split manifest.")

    train, validation, test, split = split_frames(
        frame,
        seed=int(split_manifest.get("seed", 42)),
        validation_seed=int(split_manifest.get("validation_seed", 43)),
        test_fraction=float(split_manifest.get("test_fraction", 0.15)),
        validation_fraction=float(
            split_manifest.get("validation_fraction_of_pool", 0.176470588)
        ),
    )

    new_profile = json.loads(safety_path.read_text(encoding="utf-8"))
    old_profile = json.loads(compare_path.read_text(encoding="utf-8"))
    model, path, entry, _metadata, _safety = load_verified_model(
        model_path, allow_unregistered=True
    )
    entry = {
        "model_version": version,
        "sha256": sha256_file(model_path),
        "provenance": "synthetic",
    }

    before = _summarize(_assess_rows(test, old_profile))
    after = _summarize(_assess_rows(test, new_profile))
    probes = [_run_probe(model, entry, new_profile, probe) for probe in PROBES]

    parity_rows = []
    parity_diffs = []
    for row in test[
        ["livestock_type", "breed", "sex", "age_months", "weight_kg"]
    ].itertuples(index=False, name=None):
        values = {
            "livestock_type": row[0],
            "breed": row[1],
            "sex": row[2],
            "age_months": float(row[3]),
            "weight_kg": float(row[4]),
        }
        if assess_safety(values, old_profile).status == "withheld":
            continue
        if assess_safety(values, new_profile).status == "withheld":
            continue
        old_price = predict(
            row[0],
            row[1],
            row[2],
            float(row[3]),
            float(row[4]),
            model=model,
            model_entry=entry,
            safety_profile=old_profile,
        ).price
        new_price = predict(
            row[0],
            row[1],
            row[2],
            float(row[3]),
            float(row[4]),
            model=model,
            model_entry=entry,
            safety_profile=new_profile,
        ).price
        if old_price is None or new_price is None:
            continue
        parity_rows.append(1)
        parity_diffs.append(abs(old_price - new_price))

    failures = [probe for probe in probes if not probe["passed"]]

    report: dict[str, Any] = {
        "generated_at_utc": datetime.now(timezone.utc).strftime(
            "%Y-%m-%dT%H:%M:%SZ"
        ),
        "model": {
            "version": version,
            "file": path.name,
            "sha256": sha256_file(model_path),
        },
        "dataset": {
            "filename": dataset_summary["filename"],
            "sha256": dataset_summary["sha256"],
            "provenance": "synthetic",
        },
        "split": {
            "manifest": split_manifest_path.name,
            "rows": split["rows"],
            "feature_group_overlap": split["feature_group_overlap"],
        },
        "profiles": {
            "original": {
                "file": compare_path.name,
                "schema_version": old_profile.get("schema_version", 1),
                "sha256": sha256_file(compare_path),
            },
            "revised": {
                "file": safety_path.name,
                "schema_version": new_profile.get("schema_version"),
                "sha256": sha256_file(safety_path),
            },
        },
        "before": before,
        "after": after,
        "delta": {
            "ok": after["status_counts"]["ok"] - before["status_counts"]["ok"],
            "warning": (
                after["status_counts"]["warning"]
                - before["status_counts"]["warning"]
            ),
            "withheld": (
                after["status_counts"]["withheld"]
                - before["status_counts"]["withheld"]
            ),
            "breed_only_warnings": (
                after["breed_only_warnings"] - before["breed_only_warnings"]
            ),
        },
        "probes": probes,
        "probe_failures": failures,
        "prediction_parity": {
            "rows_compared": len(parity_rows),
            "max_abs_price_difference": (
                round(max(parity_diffs), 6) if parity_diffs else 0.0
            ),
        },
        "limitations": [
            "Synthetic data only; growth windows are prototype plausibility "
            "bounds, not veterinary standards.",
            "Test-row coverage is measured on the same distribution the model "
            "was trained on; probes carry the out-of-distribution evidence.",
            "The revised profile is an untracked sidecar; activation must copy "
            "it to the registered .safety.json path.",
        ],
    }

    report_path = report_path or REPORTS_DIR / (
        f"candidate_{version}_safety_coverage_"
        f"{datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')}.json"
    )
    report_path.write_text(
        json.dumps(report, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )
    return report_path, report


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Compare original and revised candidate safety profiles."
    )
    parser.add_argument("--version", default=MODEL_VERSION)
    parser.add_argument("--model", type=Path, default=None)
    parser.add_argument("--safety-profile", type=Path, default=None)
    parser.add_argument("--compare-profile", type=Path, default=None)
    parser.add_argument("--dataset", type=Path, default=DATASET_PATH)
    parser.add_argument("--split-manifest", type=Path, default=None)
    parser.add_argument("--report", type=Path, default=None)
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    try:
        report_path, report = evaluate(
            version=args.version,
            model_path=args.model,
            safety_path=args.safety_profile,
            compare_path=args.compare_profile,
            dataset_path=args.dataset,
            split_manifest_path=args.split_manifest,
            report_path=args.report,
        )
    except (FileNotFoundError, ValueError, KeyError) as exc:
        print(f"Safety evaluation failed: {exc}")
        return 1

    before = report["before"]["status_counts"]
    after = report["after"]["status_counts"]
    print(f"Report: {report_path}")
    print(
        "State 1/2/3 before: "
        f"{before['ok']}/{before['warning']}/{before['withheld']}"
    )
    print(
        "State 1/2/3 after:  "
        f"{after['ok']}/{after['warning']}/{after['withheld']}"
    )
    print(
        "Breed-only false warnings before/after: "
        f"{report['before']['breed_only_warnings']}/"
        f"{report['after']['breed_only_warnings']}"
    )
    print(
        "Probe failures: "
        f"{len(report['probe_failures'])} of {len(report['probes'])}"
    )
    for failure in report["probe_failures"]:
        print(
            f"  FAIL {failure['probe']}: {failure['status']} "
            f"({','.join(failure['reason_codes']) or '-'})"
        )
    print(
        "Prediction parity max abs diff: "
        f"{report['prediction_parity']['max_abs_price_difference']}"
    )
    return 0 if not report["probe_failures"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
