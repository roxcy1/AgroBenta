"""Training-profile and out-of-distribution helpers.

A ``.cbm`` file contains the model but not the training ranges. Each saved model
therefore gets a small sidecar JSON with the numeric ranges and the observed
category/breed combinations. ``predict.py`` uses it to warn when an input is
outside the data the model was trained on.
"""

from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Mapping

import numpy as np
import pandas as pd

from features import NUMERIC_FEATURES, TARGET_COLUMN

PROFILE_SUFFIX = ".metadata.json"
SAFETY_SUFFIX = ".safety.json"
SAFETY_SCHEMA_VERSION = 1
PROFILE_WARNING = (
    "Synthetic training data only. Do not interpret this profile as real-market "
    "price evidence."
)
SAFETY_WARNING = (
    "Data-derived prototype safety envelope. It is based only on synthetic "
    "training rows, not authoritative biological limits or market evidence."
)

# Age-bin min/max are observed training support, not biological proof. A
# two-fold margin allows plausible animals just outside a sparse synthetic bin
# to receive a warning, while still withholding inputs far outside the observed
# joint support. Category-level extremes remain hard.
AGE_WEIGHT_SUPPORT_MARGIN = 2.0


def profile_path(model_path: Path) -> Path:
    """Return the sidecar path for a saved model."""
    return Path(model_path).with_suffix(PROFILE_SUFFIX)


def build_training_profile(
    frame: pd.DataFrame,
    *,
    model_file: str,
    provenance: str = "synthetic",
) -> dict[str, Any]:
    """Build the numeric and categorical profile of the training rows."""
    ranges: dict[str, dict[str, float]] = {}
    for column in NUMERIC_FEATURES:
        series = pd.to_numeric(frame[column], errors="raise")
        ranges[column] = {
            "min": float(series.min()),
            "max": float(series.max()),
            "p01": float(series.quantile(0.01)),
            "p99": float(series.quantile(0.99)),
        }

    observed_categories = sorted(
        str(value) for value in frame["livestock_type"].unique()
    )
    observed_breeds = {
        str(category): sorted(
            str(value) for value in group["breed"].unique()
        )
        for category, group in frame.groupby("livestock_type", sort=True)
    }

    return {
        "model_file": model_file,
        "training_rows": int(len(frame)),
        "dataset_provenance": provenance,
        "feature_ranges": ranges,
        "observed_categories": observed_categories,
        "observed_breeds": observed_breeds,
        "target": {
            "name": TARGET_COLUMN,
            "unit": "PHP",
            "min": float(frame[TARGET_COLUMN].min()),
            "max": float(frame[TARGET_COLUMN].max()),
        },
        "warning": PROFILE_WARNING,
    }


def save_training_profile(model_path: Path, profile: Mapping[str, Any]) -> Path:
    """Write a model's training-profile sidecar as UTF-8 JSON."""
    path = profile_path(model_path)
    path.write_text(
        json.dumps(profile, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )
    return path


def load_training_profile(model_path: Path) -> dict[str, Any] | None:
    """Load a sidecar profile, or ``None`` when it is absent/unreadable."""
    path = profile_path(model_path)
    if not path.is_file():
        return None
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return None


def out_of_distribution_warnings(
    values: Mapping[str, Any],
    profile: Mapping[str, Any] | None,
) -> list[str]:
    """Return human-readable warnings for values outside the training profile.

    An unsupported category/breed is normally rejected earlier by
    ``validate_feature_values``. This check also catches a globally supported
    combination that happened not to appear in a particular training split.
    """
    if not profile:
        return []

    warnings: list[str] = []
    ranges = profile.get("feature_ranges", {})

    for feature in NUMERIC_FEATURES:
        bounds = ranges.get(feature)
        if not isinstance(bounds, Mapping):
            continue
        value = float(values[feature])
        minimum = float(bounds["min"])
        maximum = float(bounds["max"])
        if value < minimum or value > maximum:
            warnings.append(
                f"{feature}={value:g} is outside the training range "
                f"[{minimum:g}, {maximum:g}]."
            )

    category = str(values["livestock_type"])
    breed = str(values["breed"])
    observed_categories = set(profile.get("observed_categories", []))
    observed_breeds = profile.get("observed_breeds", {})

    if category not in observed_categories:
        warnings.append(
            f"livestock_type={category!r} was not observed in the training data."
        )
    else:
        known_breeds = set(observed_breeds.get(category, []))
        if breed not in known_breeds:
            warnings.append(
                f"breed={breed!r} was not observed for {category} in the "
                "training data."
            )

    return warnings


# ---------------------------------------------------------------------------
# Phase 5 safety profiles
# ---------------------------------------------------------------------------


@dataclass(frozen=True)
class SafetyAssessment:
    """Structured safety decision for one prediction input."""

    status: str
    reason_codes: tuple[str, ...]
    warnings: tuple[str, ...]


def safety_profile_path(model_path: Path) -> Path:
    """Return the safety-profile sidecar path for a saved model."""
    return Path(model_path).with_suffix(SAFETY_SUFFIX)


def _numeric_stats(series: pd.Series) -> dict[str, float]:
    values = pd.to_numeric(series, errors="raise")
    return {
        "min": float(values.min()),
        "max": float(values.max()),
        "p01": float(values.quantile(0.01)),
        "p99": float(values.quantile(0.99)),
    }


def _age_bins(category: str, group: pd.DataFrame) -> list[dict[str, Any]]:
    ages = pd.to_numeric(group["age_months"], errors="raise").to_numpy(
        dtype=float
    )
    weights = group["weight_kg"]
    minimum = float(ages.min())
    maximum = float(ages.max())

    if maximum <= minimum:
        return [
            {
                "min": minimum,
                "max": maximum,
                "max_inclusive": True,
                "rows": int(len(group)),
                "weight_kg": _numeric_stats(weights),
            }
        ]

    edges = {
        minimum,
        maximum,
        *(float(value) for value in np.quantile(ages, [0.2, 0.4, 0.6, 0.8])),
    }
    if category == "chicken" and minimum < 1.0 < maximum:
        edges.add(1.0)
    ordered = sorted(edges)

    bins: list[dict[str, Any]] = []
    for index, lower in enumerate(ordered[:-1]):
        upper = ordered[index + 1]
        if index == len(ordered) - 2:
            mask = (ages >= lower) & (ages <= upper)
            inclusive = True
        else:
            mask = (ages >= lower) & (ages < upper)
            inclusive = False
        if not mask.any():
            continue
        bins.append(
            {
                "min": lower,
                "max": upper,
                "max_inclusive": inclusive,
                "rows": int(mask.sum()),
                "weight_kg": _numeric_stats(weights.loc[mask]),
            }
        )
    return bins


def build_safety_profile(
    frame: pd.DataFrame,
    *,
    model_file: str,
    provenance: str = "synthetic",
) -> dict[str, Any]:
    """Build per-category/breed envelopes and joint age-bin weight ranges.

    The hard envelope is the observed training minimum/maximum. The typical
    range is the 1st-99th percentile. Both are data-derived prototype rules,
    not authoritative biological limits.
    """
    categories: dict[str, Any] = {}

    for category, group in frame.groupby("livestock_type", sort=True):
        breeds: dict[str, Any] = {}
        for breed, breed_group in group.groupby("breed", sort=True):
            breeds[str(breed)] = {
                "rows": int(len(breed_group)),
                "age_months": _numeric_stats(breed_group["age_months"]),
                "weight_kg": _numeric_stats(breed_group["weight_kg"]),
            }

        categories[str(category)] = {
            "rows": int(len(group)),
            "age_months": _numeric_stats(group["age_months"]),
            "weight_kg": _numeric_stats(group["weight_kg"]),
            "breeds": breeds,
            "age_bins": _age_bins(str(category), group),
        }

    return {
        "schema_version": SAFETY_SCHEMA_VERSION,
        "model_file": model_file,
        "provenance": provenance,
        "source_rows": int(len(frame)),
        "categories": categories,
        "warning": SAFETY_WARNING,
    }


def save_safety_profile(model_path: Path, profile: Mapping[str, Any]) -> Path:
    """Write a model's safety profile as UTF-8 JSON."""
    path = safety_profile_path(model_path)
    path.write_text(
        json.dumps(profile, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )
    return path


def load_safety_profile(model_path: Path) -> dict[str, Any] | None:
    """Load a model's safety profile, or ``None`` when absent/unreadable."""
    path = safety_profile_path(model_path)
    if not path.is_file():
        return None
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return None


def _append_unique(values: list[str], value: str) -> None:
    if value not in values:
        values.append(value)


def _hard_bounds_message(
    field: str, value: float, bounds: Mapping[str, Any]
) -> str:
    return (
        f"{field}={value:g} is outside the supported prototype envelope "
        f"[{float(bounds['min']):g}, {float(bounds['max']):g}]."
    )


def _typical_bounds_message(
    field: str, value: float, bounds: Mapping[str, Any]
) -> str:
    return (
        f"{field}={value:g} is outside the typical training range "
        f"[{float(bounds['p01']):g}, {float(bounds['p99']):g}]."
    )


def _find_age_bin(
    age: float, bins: list[dict[str, Any]]
) -> dict[str, Any] | None:
    for age_bin in bins:
        lower = float(age_bin["min"])
        upper = float(age_bin["max"])
        if age_bin.get("max_inclusive"):
            if lower <= age <= upper:
                return age_bin
        elif lower <= age < upper:
            return age_bin
    return None


def assess_safety(
    values: Mapping[str, Any],
    profile: Mapping[str, Any] | None,
) -> SafetyAssessment:
    """Classify a validated input as ok, warning, or withheld.

    Hard failures use the observed category minimum/maximum or the joint
    age-bin weight minimum/maximum. Typical-range excursions are warnings.
    A missing profile fails closed.
    """
    reason_codes: list[str] = []
    warnings: list[str] = []

    if not profile:
        return SafetyAssessment(
            status="withheld",
            reason_codes=("missing_safety_profile",),
            warnings=(
                "No safety profile is available for this model; the prediction "
                "was withheld.",
            ),
        )

    category = str(values["livestock_type"])
    breed = str(values["breed"])
    category_profile = profile.get("categories", {}).get(category)
    if not isinstance(category_profile, Mapping):
        return SafetyAssessment(
            status="withheld",
            reason_codes=("unsupported_category_for_model",),
            warnings=(f"{category!r} is not covered by this model.",),
        )

    breed_profile = category_profile.get("breeds", {}).get(breed)
    if not isinstance(breed_profile, Mapping):
        return SafetyAssessment(
            status="withheld",
            reason_codes=("unsupported_breed_for_model",),
            warnings=(f"{breed!r} is not covered by this model for {category}.",),
        )

    age = float(values["age_months"])
    weight = float(values["weight_kg"])
    age_bounds = category_profile["age_months"]
    weight_bounds = category_profile["weight_kg"]

    hard_age = age < float(age_bounds["min"]) or age > float(age_bounds["max"])
    hard_weight = weight < float(weight_bounds["min"]) or weight > float(
        weight_bounds["max"]
    )

    if hard_age:
        _append_unique(reason_codes, "outside_supported_age")
        warnings.append(_hard_bounds_message("age_months", age, age_bounds))
    if hard_weight:
        _append_unique(reason_codes, "outside_supported_weight")
        warnings.append(
            _hard_bounds_message("weight_kg", weight, weight_bounds)
        )

    if hard_age or hard_weight:
        return SafetyAssessment(
            status="withheld",
            reason_codes=tuple(reason_codes),
            warnings=tuple(warnings),
        )

    if age < float(age_bounds["p01"]) or age > float(age_bounds["p99"]):
        _append_unique(reason_codes, "outside_typical_age")
        warnings.append(_typical_bounds_message("age_months", age, age_bounds))
    if weight < float(weight_bounds["p01"]) or weight > float(
        weight_bounds["p99"]
    ):
        _append_unique(reason_codes, "outside_typical_weight")
        warnings.append(
            _typical_bounds_message("weight_kg", weight, weight_bounds)
        )

    breed_age_bounds = breed_profile["age_months"]
    breed_weight_bounds = breed_profile["weight_kg"]
    if age < float(breed_age_bounds["p01"]) or age > float(
        breed_age_bounds["p99"]
    ):
        _append_unique(reason_codes, "outside_typical_breed_age")
        warnings.append(
            _typical_bounds_message(
                "age_months for breed", age, breed_age_bounds
            )
        )
    if weight < float(breed_weight_bounds["p01"]) or weight > float(
        breed_weight_bounds["p99"]
    ):
        _append_unique(reason_codes, "outside_typical_breed_weight")
        warnings.append(
            _typical_bounds_message(
                "weight_kg for breed", weight, breed_weight_bounds
            )
        )

    age_bin = _find_age_bin(age, category_profile.get("age_bins", []))
    if age_bin is None:
        return SafetyAssessment(
            status="withheld",
            reason_codes=("outside_supported_age_weight",),
            warnings=(
                f"No joint age-weight coverage exists for age_months={age:g}.",
            ),
        )

    bin_weight = age_bin["weight_kg"]
    bin_min = float(bin_weight["min"])
    bin_max = float(bin_weight["max"])

    # The observed age-bin min/max is sparse synthetic support, not a
    # biological boundary. Withhold only when the input is far outside that
    # support envelope; plausible edge cases remain warnings.
    support_min = max(float(weight_bounds["min"]), bin_min / AGE_WEIGHT_SUPPORT_MARGIN)
    support_max = min(float(weight_bounds["max"]), bin_max * AGE_WEIGHT_SUPPORT_MARGIN)

    if weight < support_min or weight > support_max:
        return SafetyAssessment(
            status="withheld",
            reason_codes=("insufficient_model_support",),
            warnings=(
                f"weight_kg={weight:g} is outside the model's observed age-bin "
                f"support envelope [{support_min:g}, {support_max:g}] for "
                f"age_months={age:g}. This is a model-coverage limit, not a "
                "biological determination.",
            ),
        )
    if weight < float(bin_weight["p01"]) or weight > float(bin_weight["p99"]):
        _append_unique(reason_codes, "outside_typical_age_weight")
        warnings.append(
            _typical_bounds_message(
                "weight_kg for this age band", weight, bin_weight
            )
        )

    return SafetyAssessment(
        status="warning" if warnings else "ok",
        reason_codes=tuple(reason_codes),
        warnings=tuple(warnings),
    )
