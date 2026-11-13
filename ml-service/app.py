"""Private FastAPI wrapper around the verified AgroBenta prediction pipeline.

Run locally:

    python app.py
    # or: uvicorn app:app --host 127.0.0.1 --port 8002

The service binds to localhost by default, loads one verified model at startup,
and reuses it for every request. It does not train, promote models, or expose
model file paths.
"""

from __future__ import annotations

import logging
from contextlib import asynccontextmanager
from pathlib import Path
from typing import Literal

import uvicorn
from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from pydantic import BaseModel, ConfigDict, Field

from features import InputValidationError
from model_registry import (
    ModelConfigurationError,
    ModelIntegrityError,
    load_verified_model,
)
from predict import PredictionResult, predict

LOGGER = logging.getLogger("agrobenta.ml")
PREDICTION_CONTRACT_VERSION = "1.0"
PredictionStatus = Literal[
    "ok", "warning", "withheld", "invalid", "unavailable", "error"
]


class PredictionRequest(BaseModel):
    """The five canonical model inputs; months and kilograms."""

    model_config = ConfigDict(extra="forbid", allow_inf_nan=False)

    livestock_type: str
    breed: str
    sex: str
    age_months: float = Field(gt=0, le=300)
    weight_kg: float = Field(gt=0, le=99_999_999.99)


class PredictionResponse(BaseModel):
    contract_version: str
    status: PredictionStatus
    predicted_price_php: float | None
    model_version: str | None
    model_sha256: str | None
    provenance: str | None
    warnings: list[str] = Field(default_factory=list)
    reason_codes: list[str] = Field(default_factory=list)


def _response(
    *,
    status: PredictionStatus,
    price: float | None,
    version: str | None = None,
    sha256: str | None = None,
    provenance: str | None = None,
    warnings: list[str] | None = None,
    reasons: list[str] | None = None,
) -> PredictionResponse:
    return PredictionResponse(
        contract_version=PREDICTION_CONTRACT_VERSION,
        status=status,
        predicted_price_php=price,
        model_version=version,
        model_sha256=sha256,
        provenance=provenance,
        warnings=warnings or [],
        reason_codes=reasons or [],
    )


def _model_meta(app: FastAPI) -> tuple[str | None, str | None, str | None]:
    model = getattr(app.state, "model", None)
    if model is None:
        return None, None, None
    entry = getattr(app.state, "entry", {}) or {}
    return (
        entry.get("model_version"),
        entry.get("sha256"),
        entry.get("provenance"),
    )


def create_app(
    model_path: Path | None = None,
    models_dir: Path | None = None,
) -> FastAPI:
    """Create the API app. Tests may inject a specific registered model."""

    @asynccontextmanager
    async def lifespan(application: FastAPI):
        application.state.model = None
        application.state.model_path = None
        application.state.entry = {}
        application.state.metadata = {}
        application.state.safety = {}
        application.state.startup_error = None
        application.state.load_count = 0
        try:
            model, path, entry, metadata, safety = load_verified_model(
                model_path,
                models_dir=models_dir,
            )
            application.state.model = model
            application.state.model_path = path
            application.state.entry = entry
            application.state.metadata = metadata
            application.state.safety = safety
            application.state.load_count = 1
            LOGGER.info("Loaded model %s", entry.get("model_version"))
        except Exception as exc:  # noqa: BLE001 - startup must fail safely
            application.state.startup_error = type(exc).__name__
            LOGGER.error("Model startup failed (%s)", type(exc).__name__)
            LOGGER.debug("Model startup detail", exc_info=True)
        yield
        application.state.model = None

    application = FastAPI(
        title="AgroBenta Price Prediction",
        version="1.0.0",
        lifespan=lifespan,
    )

    @application.get("/health")
    def health() -> dict[str, str]:
        return {"status": "ok"}

    @application.get("/ready")
    def ready():
        model = getattr(application.state, "model", None)
        if model is None:
            return JSONResponse(
                status_code=503,
                content={
                    "status": "not_ready",
                    "contract_version": PREDICTION_CONTRACT_VERSION,
                    "reason_codes": ["model_unavailable"],
                },
            )
        version, sha256, provenance = _model_meta(application)
        return {
            "status": "ready",
            "contract_version": PREDICTION_CONTRACT_VERSION,
            "model_version": version,
            "model_sha256": sha256,
            "provenance": provenance,
        }

    @application.post("/v1/predict", response_model=PredictionResponse)
    @application.post("/predict", response_model=PredictionResponse)
    def predict_endpoint(
        payload: PredictionRequest,
        request: Request,
    ):
        model = getattr(request.app.state, "model", None)
        if model is None:
            return JSONResponse(
                status_code=503,
                content=_response(
                    status="unavailable",
                    price=None,
                    warnings=["Prediction service is not ready."],
                    reasons=["model_unavailable"],
                ).model_dump(),
            )

        try:
            result: PredictionResult = predict(
                livestock_type=payload.livestock_type,
                breed=payload.breed,
                sex=payload.sex,
                age_months=payload.age_months,
                weight_kg=payload.weight_kg,
                model=model,
                model_path=request.app.state.model_path,
                model_entry=request.app.state.entry,
                safety_profile=request.app.state.safety,
            )
        except InputValidationError as exc:
            return JSONResponse(
                status_code=422,
                content=_response(
                    status="invalid",
                    price=None,
                    warnings=[str(exc)],
                    reasons=["invalid_input"],
                ).model_dump(),
            )
        except (ModelConfigurationError, ModelIntegrityError):
            LOGGER.exception("Model became unavailable during prediction")
            return JSONResponse(
                status_code=503,
                content=_response(
                    status="unavailable",
                    price=None,
                    warnings=["Prediction service is not ready."],
                    reasons=["model_unavailable"],
                ).model_dump(),
            )
        except Exception:  # noqa: BLE001 - do not expose internals
            LOGGER.error("Unexpected inference failure")
            LOGGER.debug("Inference detail", exc_info=True)
            return JSONResponse(
                status_code=500,
                content=_response(
                    status="error",
                    price=None,
                    warnings=["Internal prediction error."],
                    reasons=["inference_failure"],
                ).model_dump(),
            )

        response = _response(
            status=result.status,
            price=result.price,
            version=result.model_version,
            sha256=result.model_sha256,
            provenance=result.provenance,
            warnings=list(result.warnings),
            reasons=list(result.reason_codes),
        )
        if result.status == "withheld":
            return JSONResponse(status_code=422, content=response.model_dump())
        return response

    @application.exception_handler(RequestValidationError)
    async def validation_error_handler(
        _request: Request,
        exc: RequestValidationError,
    ) -> JSONResponse:
        return JSONResponse(
            status_code=422,
            content=_response(
                status="invalid",
                price=None,
                warnings=[
                    f"{'.'.join(str(part) for part in error['loc'])}: "
                    f"{error['msg']}"
                    for error in exc.errors()
                ],
                reasons=["invalid_request"],
            ).model_dump(),
        )

    @application.exception_handler(InputValidationError)
    async def input_error_handler(
        _request: Request,
        exc: InputValidationError,
    ) -> JSONResponse:
        return JSONResponse(
            status_code=422,
            content=_response(
                status="invalid",
                price=None,
                warnings=[str(exc)],
                reasons=["invalid_input"],
            ).model_dump(),
        )

    @application.exception_handler(ModelConfigurationError)
    @application.exception_handler(ModelIntegrityError)
    async def model_error_handler(
        _request: Request,
        _exc: Exception,
    ) -> JSONResponse:
        LOGGER.error("Model configuration/integrity error")
        return JSONResponse(
            status_code=503,
            content=_response(
                status="unavailable",
                price=None,
                warnings=["Prediction service is not ready."],
                reasons=["model_unavailable"],
            ).model_dump(),
        )

    @application.exception_handler(Exception)
    async def unexpected_error_handler(
        _request: Request,
        _exc: Exception,
    ) -> JSONResponse:
        LOGGER.exception("Unhandled API error")
        return JSONResponse(
            status_code=500,
            content=_response(
                status="error",
                price=None,
                warnings=["Internal prediction error."],
                reasons=["inference_failure"],
            ).model_dump(),
        )

    return application


app = create_app()


if __name__ == "__main__":
    uvicorn.run("app:app", host="127.0.0.1", port=8002, reload=False)
