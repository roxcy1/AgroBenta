"""Derive the corrected v5 synthetic dataset from the approved 4,000-row source.

The source ``data/final_livestock_sales.csv`` is never modified. This script
writes a new, separately versioned CSV plus a correction log:

    data/livestock_sales_v5_synthetic.csv
    reports/v5_correction_log.json

Corrections applied (all documented in the log):

1. Breed display names are mapped to the canonical slugs already declared in
   :mod:`features`. No new breed is introduced.
2. ``livestock_type`` and ``sex`` are stripped and lowercased.
3. Clearly implausible age/weight combinations are corrected with generous
   category age-band windows. Weights are clamped to the nearest plausible
   bound; the 1-month swine cohort is rescaled into the narrow band allowed by
   the approved 10 kg minimum. Prices are held constant, so the implied
   PHP/kg of a corrected animal reflects the corrected weight.
4. A documented 3% female breeding-stock premium is applied to sexually mature
   cattle, carabao, goat and swine. This is an explicit market assumption, not
   an observed effect; it is deliberately small.
5. Identical feature vectors with different prices are re-measured after the
   corrections. Spreads above 10% are treated as generation duplication and
   the higher price is pulled back inside 10%. Smaller spreads are documented
   as legitimate transaction-level variation and retained.

Run from the ml-service directory::

    python build_v5_dataset.py
"""

from __future__ import annotations

import hashlib
import json
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import pandas as pd

from features import REQUIRED_COLUMNS, SUPPORTED_BREEDS, parse_peso_price

BASE_DIR = Path(__file__).resolve().parent
SOURCE_PATH = BASE_DIR / "data" / "final_livestock_sales.csv"
OUTPUT_PATH = BASE_DIR / "data" / "livestock_sales_v5_synthetic.csv"
LOG_PATH = BASE_DIR / "reports" / "v5_correction_log.json"

# Display name -> existing canonical slug from features.SUPPORTED_BREEDS.
BREED_MAP: dict[str, str] = {
    "Brahman": "brahman",
    "Brahman Cross": "brahman_cross",
    "Holstein Friesian": "holstein_friesian",
    "Philippine Native Cattle": "philippine_native_cattle",
    "Murrah": "murrah",
    "Native\u2013Murrah Cross": "native_murrah_cross",
    "Philippine Native Carabao": "philippine_native_carabao",
    "Anglo-Nubian": "anglo_nubian",
    "Boer": "boer",
    "Saanen": "saanen",
    "Ubay/Boholano Native Goat": "ubay_boholano_native_goat",
    "Duroc": "duroc",
    "Duroc\u2013Landrace Cross": "duroc_landrace_cross",
    "Landrace": "landrace",
    "Large White (Yorkshire)": "large_white_yorkshire",
    "Native Pig": "native_pig",
    "Boholano Native Chicken": "boholano_native_chicken",
    "Broiler": "broiler",
    "Improved Native Chicken": "improved_native_chicken",
    "Layer": "layer",
}

EFFECTIVE_BREEDS = {
    (category, breed)
    for category, breeds in SUPPORTED_BREEDS.items()
    for breed in breeds
}

# Approved listing weight limits. Corrections never leave these bounds.
APPROVED_WEIGHT_LIMITS: dict[str, tuple[float, float]] = {
    "cattle": (50.0, 400.0),
    "carabao": (50.0, 450.0),
    "goat": (10.0, 80.0),
    "swine": (10.0, 200.0),
    "chicken": (0.3, 10.0),
}

# Generous age-band windows for "clearly implausible" weights. They are wide
# on purpose: only egregious records should move, so ordinary biological
# variation survives untouched.
AGE_WEIGHT_WINDOWS: dict[str, tuple[tuple[float, float, float, float], ...]] = {
    "cattle": (
        (2, 3, 40, 100),
        (4, 8, 50, 155),
        (9, 14, 60, 230),
        (15, 24, 105, 280),
        (25, 36, 125, 360),
        (37, 300, 140, 400),
    ),
    "carabao": (
        (2, 3, 35, 90),
        (4, 8, 45, 155),
        (9, 14, 60, 230),
        (15, 24, 100, 280),
        (25, 36, 130, 360),
        (37, 300, 150, 450),
    ),
    "goat": (
        (2, 3, 4, 22),
        (4, 6, 6, 40),
        (7, 12, 10, 48),
        (13, 24, 14, 80),
        (25, 300, 18, 80),
    ),
    "swine": (
        (1, 1, 10, 13),
        (2, 2, 10, 29),
        (3, 3, 16, 70),
        (4, 5, 25, 90),
        (6, 8, 45, 160),
        (9, 12, 60, 185),
        (13, 24, 70, 200),
        (25, 300, 65, 200),
    ),
    "chicken": (
        (1, 1, 0.1, 2.0),
        (2, 2, 0.2, 2.8),
        (3, 3, 0.3, 3.6),
        (4, 6, 0.5, 4.6),
        (7, 12, 0.6, 6.2),
        (13, 300, 0.7, 10.0),
    ),
}

SWINE_ONE_MONTH_BAND = (10.0, 13.0)
BREEDING_PREMIUM_CATEGORIES = ("cattle", "carabao", "goat", "swine")
BREEDING_PREMIUM_AGE_MONTHS = 12
BREEDING_PREMIUM_FACTOR = 1.03
CONFLICT_TOLERANCE = 0.10


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _round5(value: float) -> int:
    if value <= 0:
        raise ValueError("Price must stay positive.")
    return max(5, int(round(value / 5.0)) * 5)


def _window(category: str, age: float) -> tuple[float, float] | None:
    for low, high, weight_low, weight_high in AGE_WEIGHT_WINDOWS[category]:
        if low <= age <= high:
            return weight_low, weight_high
    return None


def canonicalize(frame: pd.DataFrame) -> pd.DataFrame:
    """Map display labels to canonical slugs and normalize text columns."""
    out = frame.copy()
    out["livestock_type"] = out["livestock_type"].str.strip().str.lower()
    out["sex"] = out["sex"].str.strip().str.lower()
    mapped = out["breed"].map(BREED_MAP)
    unmapped = sorted(out.loc[mapped.isna(), "breed"].unique())
    if unmapped:
        raise ValueError(f"Unmapped breed labels: {unmapped}")
    out["breed"] = mapped
    return out


def audit_breeds(frame: pd.DataFrame) -> list[str]:
    errors: list[str] = []
    pairs = {
        (str(category), str(breed))
        for category, breed in frame[["livestock_type", "breed"]].itertuples(
            index=False, name=None
        )
    }
    if pairs != EFFECTIVE_BREEDS:
        errors.append(
            "breed pairs differ from features.SUPPORTED_BREEDS: missing "
            f"{sorted(EFFECTIVE_BREEDS - pairs)}, unexpected "
            f"{sorted(pairs - EFFECTIVE_BREEDS)}"
        )
    counts = frame.groupby(["livestock_type", "breed"]).size()
    for pair, count in sorted(counts.items()):
        if count != 200:
            errors.append(f"{pair[0]}/{pair[1]} has {count} rows, expected 200")
    return errors


def _record(
    frame: pd.DataFrame,
    index: int,
    original: float,
    corrected: float,
    rule: str,
    reason: str,
) -> dict[str, Any]:
    return {
        "row": int(index) + 2,
        "category": str(frame.at[index, "livestock_type"]),
        "breed": str(frame.at[index, "breed"]),
        "sex": str(frame.at[index, "sex"]),
        "age_months": float(frame.at[index, "age_months"]),
        "from_kg": round(original, 2),
        "to_kg": round(corrected, 2),
        "rule": rule,
        "reason": reason,
    }


def _break_ties(
    frame: pd.DataFrame, corrections: list[dict[str, Any]]
) -> None:
    """Keep corrected weights distinct so no exact duplicate row is created."""
    key_columns = ["livestock_type", "breed", "sex", "age_months"]
    corrected_rows = {entry["row"] - 2 for entry in corrections}
    taken: set[tuple[Any, ...]] = {
        (*tuple(frame.at[index, column] for column in key_columns),
         float(frame.at[index, "weight_kg"]))
        for index in frame.index
        if index not in corrected_rows
    }
    for index in sorted(corrected_rows):
        values = tuple(frame.at[index, column] for column in key_columns)
        candidate = float(frame.at[index, "weight_kg"])
        guard = 0
        while (*values, candidate) in taken:
            candidate = round(candidate - 0.01, 2)
            guard += 1
            if guard > 20:
                raise ValueError("Could not break a weight tie after correction")
        if candidate != float(frame.at[index, "weight_kg"]):
            for entry in corrections:
                if entry["row"] - 2 == index:
                    entry["to_kg"] = candidate
                    entry["reason"] += " (0.01 kg tie-break applied)"
                    break
            frame.at[index, "weight_kg"] = candidate
        taken.add((*values, candidate))


def correct_weights(
    frame: pd.DataFrame,
) -> tuple[pd.DataFrame, list[dict[str, Any]], list[dict[str, Any]]]:
    """Correct clearly implausible weights, keeping the approved limits.

    Out-of-window weights are compressed into a narrow band just inside the
    plausible bound instead of being flattened onto it. That keeps records
    distinct and avoids piling every correction on one value.
    """
    out = frame.copy()
    corrections: list[dict[str, Any]] = []
    flagged: list[dict[str, Any]] = []

    swine_mask = (out["livestock_type"] == "swine") & (out["age_months"] == 1)
    if swine_mask.any():
        cohort = out.loc[swine_mask, "weight_kg"]
        low, high = float(cohort.min()), float(cohort.max())
        band_low, band_high = SWINE_ONE_MONTH_BAND
        span = high - low if high > low else 1.0
        for index in cohort.index:
            original = float(out.at[index, "weight_kg"])
            corrected = round(
                band_low + (original - low) * (band_high - band_low) / span, 2
            )
            out.at[index, "weight_kg"] = corrected
            corrections.append(
                _record(
                    out,
                    index,
                    original,
                    corrected,
                    "swine_1mo_approved_range_rescale",
                    "1-month swine weights implied a ~2-month animal; the "
                    "approved 10 kg minimum forbids a true 5-9 kg weaner, so "
                    "the cohort is rescaled into the 10-13 kg band allowed by "
                    "the approved range.",
                )
            )
        flagged.append(
            {
                "category": "swine",
                "age_months": 1,
                "rows": int(swine_mask.sum()),
                "issue": (
                    "A biologically typical 1-month weaner weighs 5-9 kg, "
                    "which is below the approved 10 kg dataset minimum. The "
                    "cohort was rescaled to 10-13 kg; the approved range "
                    "itself needs data-owner review."
                ),
            }
        )

    above: dict[tuple[str, float, float], list[tuple[int, float, float]]] = {}
    below: dict[tuple[str, float, float], list[tuple[int, float, float]]] = {}
    for index in out.index[~swine_mask]:
        category = str(out.at[index, "livestock_type"])
        age = float(out.at[index, "age_months"])
        window = _window(category, age)
        if window is None:
            continue
        approved_low, approved_high = APPROVED_WEIGHT_LIMITS[category]
        lower = max(window[0], approved_low)
        upper = min(window[1], approved_high)
        original = float(out.at[index, "weight_kg"])
        bucket = (category, window[0], window[1])
        if original > upper:
            above.setdefault(bucket, []).append((index, original, upper))
        elif original < lower:
            below.setdefault(bucket, []).append((index, original, lower))

    for bucket, rows in above.items():
        excesses = [original - upper for _, original, upper in rows]
        largest = max(excesses)
        upper = rows[0][2]
        band = max(0.5, round(upper * 0.05, 2))
        for (index, original, _), excess in zip(rows, excesses):
            corrected = upper - (largest - excess) / largest * band
            corrected = round(corrected, 2)
            out.at[index, "weight_kg"] = corrected
            corrections.append(
                _record(
                    out,
                    index,
                    original,
                    corrected,
                    "age_band_compress_high",
                    f"above the plausible {bucket[0]} window ceiling "
                    f"{upper:g} kg; compressed into the upper "
                    f"{band:g} kg band instead of flattening onto the bound",
                )
            )

    for bucket, rows in below.items():
        deficits = [lower - original for _, original, lower in rows]
        largest = max(deficits)
        lower = rows[0][2]
        band = max(0.5, round(lower * 0.05, 2))
        for (index, original, _), deficit in zip(rows, deficits):
            corrected = lower + (largest - deficit) / largest * band
            corrected = round(corrected, 2)
            out.at[index, "weight_kg"] = corrected
            corrections.append(
                _record(
                    out,
                    index,
                    original,
                    corrected,
                    "age_band_compress_low",
                    f"below the plausible {bucket[0]} window floor "
                    f"{lower:g} kg; compressed into the lower "
                    f"{band:g} kg band instead of flattening onto the bound",
                )
            )

    _break_ties(out, corrections)
    return out, corrections, flagged


def apply_pricing(
    frame: pd.DataFrame,
) -> tuple[pd.DataFrame, list[dict[str, Any]]]:
    """Apply the documented female breeding-stock premium."""
    out = frame.copy()
    changes: list[dict[str, Any]] = []
    mask = (
        (out["sex"] == "female")
        & out["livestock_type"].isin(BREEDING_PREMIUM_CATEGORIES)
        & (out["age_months"] >= BREEDING_PREMIUM_AGE_MONTHS)
    )
    for index in out.index[mask]:
        original = int(out.at[index, "actual_sale_price"])
        corrected = _round5(original * BREEDING_PREMIUM_FACTOR)
        if corrected == original:
            continue
        out.at[index, "actual_sale_price"] = corrected
        changes.append(
            {
                "row": int(index) + 2,
                "from_php": original,
                "to_php": corrected,
                "reason": "female_breeding_stock_premium_3pct",
            }
        )
    return out, changes


def resolve_conflicts(
    frame: pd.DataFrame,
) -> tuple[pd.DataFrame, list[dict[str, Any]], list[dict[str, Any]]]:
    """Document identical-feature price groups; pull back >10% spreads."""
    out = frame.copy()
    groups: list[dict[str, Any]] = []
    adjustments: list[dict[str, Any]] = []
    key = list(REQUIRED_COLUMNS[:5])

    for values, group in out.groupby(key, sort=True):
        if len(group) < 2:
            continue
        prices = sorted(int(value) for value in group["actual_sale_price"])
        low, high = prices[0], prices[-1]
        spread = (high - low) / ((high + low) / 2)
        entry = {
            "livestock_type": values[0],
            "breed": values[1],
            "sex": values[2],
            "age_months": float(values[3]),
            "weight_kg": float(values[4]),
            "rows": int(len(group)),
            "prices_php": prices,
            "spread_percent": round(spread * 100, 2),
            "resolution": (
                "legitimate_transaction_variation"
                if spread <= CONFLICT_TOLERANCE
                else "capped_to_10pct"
            ),
        }
        if spread > CONFLICT_TOLERANCE:
            ceiling = _round5(low * (1 + CONFLICT_TOLERANCE))
            if ceiling <= low:
                ceiling = low + 5
            for index in group.index:
                current = int(out.at[index, "actual_sale_price"])
                if current > ceiling:
                    out.at[index, "actual_sale_price"] = ceiling
                    adjustments.append(
                        {
                            "row": int(index) + 2,
                            "from_php": current,
                            "to_php": ceiling,
                            "reason": "conflict_spread_capped_to_10pct",
                        }
                    )
        groups.append(entry)
    return out, groups, adjustments


def build() -> dict[str, Any]:
    if not SOURCE_PATH.is_file():
        raise FileNotFoundError(f"Source dataset not found: {SOURCE_PATH}")

    raw = pd.read_csv(SOURCE_PATH, encoding="utf-8-sig")
    missing = [column for column in REQUIRED_COLUMNS if column not in raw.columns]
    if missing:
        raise ValueError(f"Source is missing required columns: {missing}")
    raw = raw.loc[:, list(REQUIRED_COLUMNS)].copy()
    raw["actual_sale_price"] = raw["actual_sale_price"].map(parse_peso_price)

    frame = canonicalize(raw)
    breed_errors = audit_breeds(frame)
    if breed_errors:
        raise ValueError("; ".join(breed_errors))

    frame, weight_corrections, flagged = correct_weights(frame)
    frame, price_changes = apply_pricing(frame)
    frame, conflict_groups, conflict_adjustments = resolve_conflicts(frame)

    frame["actual_sale_price"] = frame["actual_sale_price"].astype(int)
    frame["weight_kg"] = frame["weight_kg"].astype(float).round(2)
    frame["age_months"] = frame["age_months"].astype(int)

    for category, (low, high) in APPROVED_WEIGHT_LIMITS.items():
        weights = frame.loc[frame["livestock_type"] == category, "weight_kg"]
        if weights.empty:
            continue
        if weights.min() < low or weights.max() > high:
            raise ValueError(
                f"{category} weights leave the approved range after corrections"
            )

    if len(frame) != 4000:
        raise ValueError(f"Expected 4000 rows, got {len(frame)}")
    if frame.duplicated().any():
        raise ValueError("Corrections produced exact duplicate rows")

    frame.to_csv(OUTPUT_PATH, index=False, encoding="utf-8", lineterminator="\n")

    log: dict[str, Any] = {
        "schema_version": 1,
        "generated_at_utc": datetime.now(timezone.utc).strftime(
            "%Y-%m-%dT%H:%M:%SZ"
        ),
        "source": {
            "path": SOURCE_PATH.relative_to(BASE_DIR).as_posix(),
            "sha256": _sha256(SOURCE_PATH),
            "rows": int(len(raw)),
        },
        "output": {
            "path": OUTPUT_PATH.relative_to(BASE_DIR).as_posix(),
            "sha256": _sha256(OUTPUT_PATH),
            "rows": int(len(frame)),
            "columns": list(REQUIRED_COLUMNS),
            "provenance": "synthetic",
            "provenance_label": "reviewed synthetic data, corrected for v5",
        },
        "rules": {
            "breed_mapping": BREED_MAP,
            "age_weight_windows": {
                category: [
                    {
                        "age_months": [low, high],
                        "weight_kg": [weight_low, weight_high],
                    }
                    for low, high, weight_low, weight_high in windows
                ]
                for category, windows in AGE_WEIGHT_WINDOWS.items()
            },
            "approved_weight_limits": {
                category: list(bounds)
                for category, bounds in APPROVED_WEIGHT_LIMITS.items()
            },
            "swine_1mo_band": list(SWINE_ONE_MONTH_BAND),
            "breeding_premium": {
                "categories": list(BREEDING_PREMIUM_CATEGORIES),
                "min_age_months": BREEDING_PREMIUM_AGE_MONTHS,
                "factor": BREEDING_PREMIUM_FACTOR,
                "assumption": (
                    "Mature females command a small breeding-stock premium. "
                    "This is a documented market assumption, not an observed "
                    "effect in the synthetic source."
                ),
            },
            "conflict_tolerance": CONFLICT_TOLERANCE,
            "price_rounding_php": 5,
            "weight_corrections_hold_price": True,
        },
        "summary": {
            "breed_labels_mapped": len(BREED_MAP),
            "weights_corrected": len(weight_corrections),
            "prices_changed": len(price_changes) + len(conflict_adjustments),
            "breeding_premium_rows": len(price_changes),
            "conflict_groups": len(conflict_groups),
            "conflict_groups_capped": sum(
                1
                for group in conflict_groups
                if group["resolution"] == "capped_to_10pct"
            ),
            "conflict_prices_adjusted": len(conflict_adjustments),
            "flagged_for_review": len(flagged),
            "rows": int(len(frame)),
            "breeds": len(EFFECTIVE_BREEDS),
        },
        "weight_corrections": weight_corrections,
        "price_changes": [*price_changes, *conflict_adjustments],
        "conflict_groups": conflict_groups,
        "flagged_for_review": flagged,
        "limitations": [
            "Prices remain dominated by live weight; breed, age and sex carry "
            "weak effects in this synthetic source.",
            "No price adjustment can substitute for real Bohol market sales.",
            "The approved 10 kg swine minimum conflicts with realistic 1-month "
            "weaner weights; the cohort is flagged for data-owner review.",
        ],
    }

    LOG_PATH.parent.mkdir(parents=True, exist_ok=True)
    LOG_PATH.write_text(
        json.dumps(log, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
    )
    return log


def main() -> int:
    log = build()
    summary = log["summary"]
    print(f"Source:  {log['source']['path']} sha256={log['source']['sha256']}")
    print(f"Output:  {log['output']['path']} sha256={log['output']['sha256']}")
    print(
        f"Rows: {summary['rows']}  breeds: {summary['breeds']}  "
        f"weights corrected: {summary['weights_corrected']}  "
        f"prices changed: {summary['prices_changed']}  "
        f"conflict groups: {summary['conflict_groups']}  "
        f"flagged: {summary['flagged_for_review']}"
    )
    print(f"Log:     {LOG_PATH.relative_to(BASE_DIR).as_posix()}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
