"""Load a verified AgroBenta model and produce one safety-assessed prediction.

A prediction is one of:

- ``ok``: inside the data-derived safety envelope; a price is returned.
- ``warning``: unusual but supported; a price is returned with warnings.
- ``withheld``: outside the supported envelope or unsafe; no price is returned.

The default model is selected from ``models/active_model.json``. ``MODEL_PATH``
or ``--model`` may select another registered model. Filename modification time
is not used for configured deployments.
"""

from __future__ import annotations

import argparse
import json
import math
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Mapping

import pandas as pd
from catboost import CatBoostRegressor

from features import (
    FEATURE_COLUMNS,
    InputValidationError,
    validate_feature_values,
)
from model_registry import (
    MODELS_DIR,
    ModelConfigurationError,
    ModelIntegrityError,
    load_verified_model,
)
from validation import assess_safety, load_safety_profile

MODEL_PATTERN = "catboost_price_v*.cbm"


class UnsafePredictionError(ValueError):
    """Raised when a caller requests a float but the prediction was withheld."""

    def __init__(self, message: str, result: "PredictionResult") -> None:
        super().__init__(message)
        self.result = result


@dataclass(frozen=True)
class PredictionResult:
    """Integration-ready prediction result."""

    status: str
    price: float | None
    model_path: Path | None
    model_version: str | None
    model_sha256: str | None
    provenance: str | None
    warnings: tuple[str, ...]
    reason_codes: tuple[str, ...]

    @property
    def predicted_price_php(self) -> float | None:
        return self.price


def latest_model_path(models_dir: Path | None = None) -> Path:
    """Legacy development helper; not used for configured deployments."""
    directory = MODELS_DIR if models_dir is None else Path(models_dir)
    candidates = sorted(
        directory.glob(MODEL_PATTERN),
        key=lambda path: (path.stat().st_mtime, path.name),
        reverse=True,
    )
    if not candidates:
        raise FileNotFoundError(
            f"No trained model found in {directory}. Run `python train.py` first."
        )
    return candidates[0]


def load_model(
    model_path: Path | None = None,
    *,
    models_dir: Path | None = None,
    allow_unregistered: bool = False,
) -> tuple[CatBoostRegressor, Path]:
    """Load a verified model, or an explicit test model when allowed."""
    model, path, _entry, _metadata, _safety = load_verified_model(
        model_path,
        models_dir=models_dir,
        allow_unregistered=allow_unregistered,
    )
    return model, path


def predict(
    livestock_type: str,
    breed: str,
    sex: str,
    age_months: float,
    weight_kg: float,
    model: CatBoostRegressor | None = None,
    model_path: Path | None = None,
    models_dir: Path | None = None,
    model_entry: Mapping[str, Any] | None = None,
    safety_profile: Mapping[str, Any] | None = None,
) -> PredictionResult:
    """Validate, safety-assess and predict one price.

    Severe safety failures return ``status='withheld'`` and ``price=None``.
    Moderate excursions return ``status='warning'`` with a price and warnings.
    Schema-invalid inputs still raise :class:`InputValidationError`.

    ``model_entry`` and ``safety_profile`` let a server pass the model and
    profile it verified once at startup, so requests reuse them.
    """
    values = validate_feature_values(
        livestock_type=livestock_type,
        breed=breed,
        sex=sex,
        age_months=age_months,
        weight_kg=weight_kg,
    )

    if model is None:
        active_model, path, entry, _metadata, safety = load_verified_model(
            model_path,
            models_dir=models_dir,
        )
    else:
        active_model = model
        path = Path(model_path) if model_path is not None else None
        entry = dict(model_entry) if model_entry is not None else {
            "model_version": "unregistered",
            "sha256": None,
            "provenance": "unknown",
        }
        if safety_profile is not None:
            safety = safety_profile
        else:
            safety = load_safety_profile(path) if path is not None else None

    assessment = assess_safety(values, safety)
    common = {
        "model_path": path,
        "model_version": entry.get("model_version"),
        "model_sha256": entry.get("sha256"),
        "provenance": entry.get("provenance"),
        "warnings": assessment.warnings,
        "reason_codes": assessment.reason_codes,
    }

    if assessment.status == "withheld":
        return PredictionResult(
            status="withheld",
            price=None,
            **common,
        )

    features = pd.DataFrame([values], columns=list(FEATURE_COLUMNS))
    prediction = float(active_model.predict(features)[0])

    if not math.isfinite(prediction) or prediction <= 0:
        return PredictionResult(
            status="withheld",
            price=None,
            model_path=path,
            model_version=entry.get("model_version"),
            model_sha256=entry.get("sha256"),
            provenance=entry.get("provenance"),
            warnings=("The model did not produce a positive price.",),
            reason_codes=("non_positive_prediction",),
        )

    return PredictionResult(
        status=assessment.status,
        price=prediction,
        **common,
    )


def predict_price(
    livestock_type: str,
    breed: str,
    sex: str,
    age_months: float,
    weight_kg: float,
    model: CatBoostRegressor | None = None,
    model_path: Path | None = None,
    models_dir: Path | None = None,
    model_entry: Mapping[str, Any] | None = None,
    safety_profile: Mapping[str, Any] | None = None,
) -> float:
    """Return only a price, or raise if the result was withheld."""
    result = predict(
        livestock_type=livestock_type,
        breed=breed,
        sex=sex,
        age_months=age_months,
        weight_kg=weight_kg,
        model=model,
        model_path=model_path,
        models_dir=models_dir,
        model_entry=model_entry,
        safety_profile=safety_profile,
    )
    if result.status == "withheld" or result.price is None:
        raise UnsafePredictionError(
            "Prediction withheld: " + ", ".join(result.reason_codes),
            result,
        )
    return result.price


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Predict one livestock price with the active AgroBenta model."
    )
    parser.add_argument(
        "--model",
        type=Path,
        default=None,
        help=(
            "Path to a registered .cbm file. Defaults to the active manifest, "
            "or MODEL_PATH when set."
        ),
    )
    parser.add_argument("--livestock-type", required=True)
    parser.add_argument("--breed", required=True)
    parser.add_argument("--sex", required=True)
    parser.add_argument("--age-months", type=float, required=True)
    parser.add_argument("--weight-kg", type=float, required=True)
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)

    try:
        result = predict(
            livestock_type=args.livestock_type,
            breed=args.breed,
            sex=args.sex,
            age_months=args.age_months,
            weight_kg=args.weight_kg,
            model_path=args.model,
        )
    except (
        FileNotFoundError,
        InputValidationError,
        ModelConfigurationError,
        ModelIntegrityError,
        ValueError,
    ) as exc:
        print(f"Prediction failed: {exc}", file=sys.stderr)
        return 1

    payload = {
        "status": result.status,
        "predicted_price_php": (
            round(result.price, 2) if result.price is not None else None
        ),
        "model_version": result.model_version,
        "model_sha256": result.model_sha256,
        "provenance": result.provenance,
        "warnings": list(result.warnings),
        "reason_codes": list(result.reason_codes),
        "model": str(result.model_path) if result.model_path else None,
    }
    print(json.dumps(payload, ensure_ascii=False))
    return 2 if result.status == "withheld" else 0


if __name__ == "__main__":
    raise SystemExit(main())
