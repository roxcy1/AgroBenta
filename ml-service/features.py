"""Shared feature schema and validation for the AgroBenta price model.

This module is the single definition of what the model accepts. Training and
prediction both import it, so a category or breed cannot be accepted by one and
rejected by the other.

The synthetic dataset is prototype data only. Its evaluation does not establish
real-market accuracy.
"""

from __future__ import annotations

import math
import re
from typing import Any

import pandas as pd

REQUIRED_COLUMNS: tuple[str, ...] = (
    "livestock_type",
    "breed",
    "sex",
    "age_months",
    "weight_kg",
    "actual_sale_price",
)

CATEGORICAL_FEATURES: tuple[str, ...] = ("livestock_type", "breed", "sex")
NUMERIC_FEATURES: tuple[str, ...] = ("age_months", "weight_kg")
FEATURE_COLUMNS: tuple[str, ...] = CATEGORICAL_FEATURES + NUMERIC_FEATURES
TARGET_COLUMN = "actual_sale_price"

VALID_SEXES: tuple[str, ...] = ("male", "female")

# The prototype scope explicitly includes chicken. The Laravel enum, API
# catalog, and mobile client expose the same category and canonical breeds.
SUPPORTED_BREEDS: dict[str, tuple[str, ...]] = {
    "cattle": (
        "brahman",
        "brahman_cross",
        "holstein_friesian",
        "philippine_native_cattle",
    ),
    "carabao": (
        "murrah",
        "native_murrah_cross",
        "philippine_native_carabao",
    ),
    "goat": (
        "anglo_nubian",
        "boer",
        "saanen",
        "ubay_boholano_native_goat",
    ),
    "swine": (
        "duroc",
        "duroc_landrace_cross",
        "landrace",
        "large_white_yorkshire",
        "native_pig",
    ),
    "chicken": (
        "boholano_native_chicken",
        "broiler",
        "improved_native_chicken",
        "layer",
    ),
}

SUPPORTED_CATEGORIES: tuple[str, ...] = tuple(SUPPORTED_BREEDS)

# Mirrors the backend's 25-year listing ceiling and the weight column's range.
MAX_AGE_MONTHS = 300.0
MAX_WEIGHT_KG = 99999999.99

_PESO_MARKERS = ("\u20b1", "PHP", "php", "Php")


class InputValidationError(ValueError):
    """Raised when a feature value is outside the supported contract."""


class DatasetValidationError(ValueError):
    """Raised when the training CSV does not satisfy the feature contract."""


def normalize_label(value: Any) -> str:
    """Return a trimmed, lowercase categorical value.

    ``None`` and pandas ``NaN`` become an empty string, which callers reject
    with a field-specific message rather than letting it become a category.
    """
    if value is None:
        return ""
    try:
        if pd.isna(value):
            return ""
    except (TypeError, ValueError):
        pass
    return str(value).strip().lower()


def parse_peso_price(value: Any) -> float:
    """Parse ``₱15,570``, ``PHP 15,570.00``, ``15,570`` or ``15570``.

    A value that still contains letters or other unexpected characters is
    rejected instead of being partially parsed. The result must be finite and
    strictly positive.
    """
    if isinstance(value, bool):
        raise InputValidationError("actual_sale_price must be a positive amount.")

    if isinstance(value, (int, float)):
        amount = float(value)
    else:
        text = str(value).strip().replace("\u00a0", " ")
        for marker in _PESO_MARKERS:
            text = text.replace(marker, "")
        text = text.replace(",", "").strip()
        if not re.fullmatch(r"[+-]?(?:\d+(?:\.\d*)?|\.\d+)", text):
            raise InputValidationError(
                f"actual_sale_price could not be parsed from {value!r}."
            )
        amount = float(text)

    if not math.isfinite(amount) or amount <= 0:
        raise InputValidationError("actual_sale_price must be a positive amount.")

    return amount


def _as_finite_float(value: Any, field: str) -> float:
    if isinstance(value, bool):
        raise InputValidationError(f"{field} must be numeric.")

    try:
        number = float(value)
    except (TypeError, ValueError) as exc:
        raise InputValidationError(f"{field} must be numeric.") from exc

    if not math.isfinite(number):
        raise InputValidationError(f"{field} must be a finite number.")

    return number


def validate_feature_values(
    livestock_type: Any,
    breed: Any,
    sex: Any,
    age_months: Any,
    weight_kg: Any,
) -> dict[str, Any]:
    """Normalize and validate the five model inputs.

    Returns a dictionary in ``FEATURE_COLUMNS`` order. Raises
    :class:`InputValidationError` for any unsupported combination or invalid
    value.
    """
    category = normalize_label(livestock_type)
    normalized_breed = normalize_label(breed)
    normalized_sex = normalize_label(sex)

    if category not in SUPPORTED_BREEDS:
        supported = ", ".join(SUPPORTED_CATEGORIES)
        raise InputValidationError(
            f"Unsupported livestock_type {livestock_type!r}. Supported: {supported}."
        )

    if normalized_breed not in SUPPORTED_BREEDS[category]:
        supported = ", ".join(SUPPORTED_BREEDS[category])
        raise InputValidationError(
            f"Unsupported breed {breed!r} for {category}. Supported: {supported}."
        )

    if normalized_sex not in VALID_SEXES:
        raise InputValidationError(
            f"Unsupported sex {sex!r}. Supported: {', '.join(VALID_SEXES)}."
        )

    age = _as_finite_float(age_months, "age_months")
    if age <= 0 or age > MAX_AGE_MONTHS:
        raise InputValidationError(
            f"age_months must be greater than 0 and at most {MAX_AGE_MONTHS:g}."
        )

    weight = _as_finite_float(weight_kg, "weight_kg")
    if weight <= 0 or weight > MAX_WEIGHT_KG:
        raise InputValidationError(
            f"weight_kg must be greater than 0 and at most {MAX_WEIGHT_KG:g}."
        )

    return {
        "livestock_type": category,
        "breed": normalized_breed,
        "sex": normalized_sex,
        "age_months": age,
        "weight_kg": weight,
    }


def validate_and_normalize_frame(
    frame: pd.DataFrame,
) -> tuple[pd.DataFrame, list[str]]:
    """Validate a training frame and return normalized rows plus ignored columns.

    The six required columns must be present. Extra columns are ignored and
    returned so the training report can name them; they never become features.
    """
    if not isinstance(frame, pd.DataFrame):
        raise DatasetValidationError("Dataset must be a pandas DataFrame.")

    missing = [column for column in REQUIRED_COLUMNS if column not in frame.columns]
    if missing:
        raise DatasetValidationError(
            "Dataset is missing required column(s): " + ", ".join(missing)
        )

    ignored = [str(column) for column in frame.columns if column not in REQUIRED_COLUMNS]
    records: list[dict[str, Any]] = []

    for offset, row in enumerate(
        frame.loc[:, list(REQUIRED_COLUMNS)].itertuples(index=False, name=None),
        start=2,
    ):
        try:
            values = validate_feature_values(
                livestock_type=row[0],
                breed=row[1],
                sex=row[2],
                age_months=row[3],
                weight_kg=row[4],
            )
            values[TARGET_COLUMN] = parse_peso_price(row[5])
        except (InputValidationError, ValueError) as exc:
            raise DatasetValidationError(f"Row {offset}: {exc}") from exc

        records.append(values)

    return pd.DataFrame.from_records(records, columns=list(REQUIRED_COLUMNS)), ignored
