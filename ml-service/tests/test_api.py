import os
import unittest
from pathlib import Path
from unittest.mock import patch

import pandas as pd
from fastapi.testclient import TestClient

from app import create_app
from features import SUPPORTED_BREEDS
from train import assign_split, load_and_validate_dataset
from train_young_chicken import split_young_chickens

BASE_DIR = Path(__file__).resolve().parents[1]
V3_PATH = (
    BASE_DIR
    / "models"
    / "candidate_catboost_targeted_v3_20261105T133811927044Z.cbm"
)
MISSING_PATH = BASE_DIR / "models" / "does-not-exist.cbm"


def _training_frames() -> tuple[pd.DataFrame, pd.DataFrame]:
    original, _ = load_and_validate_dataset(
        BASE_DIR / "data" / "synthetic_livestock_sales.csv"
    )
    original_train, _ = assign_split(original, 0.2, 42)
    expanded, _ = load_and_validate_dataset(
        BASE_DIR / "data" / "synthetic_livestock_sales_v2.csv"
    )
    young = expanded[
        (expanded["livestock_type"] == "chicken")
        & (expanded["age_months"] < 1.0)
    ].reset_index(drop=True)
    young_train, _, _ = split_young_chickens(young)
    return original_train, pd.concat(
        [original_train, young_train], ignore_index=True
    )


def _representatives(frame: pd.DataFrame) -> list[dict]:
    values = []
    for category in sorted(SUPPORTED_BREEDS):
        for breed in SUPPORTED_BREEDS[category]:
            subset = frame[
                (frame["livestock_type"] == category)
                & (frame["breed"] == breed)
            ]
            values.append(
                {
                    "livestock_type": category,
                    "breed": breed,
                    "sex": "male",
                    "age_months": float(subset["age_months"].median()),
                    "weight_kg": float(subset["weight_kg"].median()),
                }
            )
    return values


class ApiTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.v1_frame, cls.v3_frame = _training_frames()

    def test_health_ready_and_model_reuse(self):
        with TestClient(create_app()) as client:
            health = client.get("/health")
            ready = client.get("/ready")
            self.assertEqual(health.status_code, 200)
            self.assertEqual(ready.status_code, 200)
            self.assertEqual(ready.json()["contract_version"], "1.0")
            self.assertEqual(ready.json()["model_version"], "v1")
            self.assertEqual(client.app.state.load_count, 1)
            model_id = id(client.app.state.model)

            first = client.post(
                "/predict",
                json={
                    "livestock_type": "cattle",
                    "breed": "brahman",
                    "sex": "male",
                    "age_months": 48,
                    "weight_kg": 350,
                },
            )
            second = client.post(
                "/predict",
                json={
                    "livestock_type": "goat",
                    "breed": "boer",
                    "sex": "female",
                    "age_months": 24,
                    "weight_kg": 40,
                },
            )
            self.assertEqual(id(client.app.state.model), model_id)

        self.assertEqual(first.status_code, 200)
        self.assertEqual(second.status_code, 200)
        self.assertEqual(first.json()["contract_version"], "1.0")
        self.assertNotIn("models", first.text)
        self.assertNotIn("cbm", first.text)

    def test_versioned_predict_route(self):
        with TestClient(create_app()) as client:
            response = client.post(
                "/v1/predict",
                json={
                    "livestock_type": "cattle",
                    "breed": "brahman",
                    "sex": "male",
                    "age_months": 48,
                    "weight_kg": 350,
                },
            )
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json()["contract_version"], "1.0")
        self.assertGreater(response.json()["predicted_price_php"], 0)

    def test_active_v1_withholds_young_chicken(self):
        with TestClient(create_app()) as client:
            response = client.post(
                "/predict",
                json={
                    "livestock_type": "chicken",
                    "breed": "broiler",
                    "sex": "male",
                    "age_months": 0.098563,
                    "weight_kg": 0.5,
                },
            )
        body = response.json()
        self.assertEqual(response.status_code, 422)
        self.assertEqual(body["status"], "withheld")
        self.assertIsNone(body["predicted_price_php"])
        self.assertTrue(body["reason_codes"])

    def test_model_path_environment_selects_v3(self):
        with patch.dict(os.environ, {"MODEL_PATH": str(V3_PATH)}):
            with TestClient(create_app()) as client:
                ready = client.get("/ready")

        self.assertEqual(ready.status_code, 200)
        self.assertEqual(ready.json()["model_version"], "v3-targeted")

    def test_v3_handles_fractional_young_ages(self):
        with TestClient(create_app(model_path=V3_PATH)) as client:
            self.assertEqual(client.get("/ready").json()["model_version"], "v3-targeted")
            for day in (3, 10, 15, 20, 30):
                response = client.post(
                    "/predict",
                    json={
                        "livestock_type": "chicken",
                        "breed": "broiler",
                        "sex": "male",
                        "age_months": day / 30.4375,
                        "weight_kg": 0.5,
                    },
                )
                self.assertEqual(response.status_code, 200)
                self.assertGreater(response.json()["predicted_price_php"], 0)

            one_month = client.post(
                "/predict",
                json={
                    "livestock_type": "chicken",
                    "breed": "broiler",
                    "sex": "male",
                    "age_months": 1.0,
                    "weight_kg": 0.5,
                },
            )
            self.assertEqual(one_month.status_code, 200)
            self.assertEqual(one_month.json()["status"], "warning")
            self.assertGreater(one_month.json()["predicted_price_php"], 0)

    def test_all_20_breed_combinations(self):
        with TestClient(create_app(model_path=V3_PATH)) as client:
            for values in _representatives(self.v3_frame):
                with self.subTest(values=values):
                    response = client.post("/predict", json=values)
                    self.assertEqual(response.status_code, 200)
                    self.assertIn(response.json()["status"], ("ok", "warning"))
                    self.assertGreater(response.json()["predicted_price_php"], 0)

    def test_warning_returns_price(self):
        with TestClient(create_app(model_path=V3_PATH)) as client:
            response = client.post(
                "/predict",
                json={
                    "livestock_type": "cattle",
                    "breed": "brahman",
                    "sex": "male",
                    "age_months": 48,
                    "weight_kg": 510,
                },
            )
        body = response.json()
        self.assertEqual(response.status_code, 200)
        self.assertEqual(body["status"], "warning")
        self.assertIsNotNone(body["predicted_price_php"])
        self.assertIn("outside_typical_age_weight", body["reason_codes"])

    def test_withheld_never_returns_price(self):
        with TestClient(create_app(model_path=V3_PATH)) as client:
            response = client.post(
                "/predict",
                json={
                    "livestock_type": "chicken",
                    "breed": "broiler",
                    "sex": "male",
                    "age_months": 0.098563,
                    "weight_kg": 500,
                },
            )
        body = response.json()
        self.assertEqual(response.status_code, 422)
        self.assertEqual(body["status"], "withheld")
        self.assertIsNone(body["predicted_price_php"])
        self.assertIn("outside_supported_weight", body["reason_codes"])

    def test_invalid_inputs_are_structured_422(self):
        with TestClient(create_app(model_path=V3_PATH)) as client:
            cases = [
                {
                    "livestock_type": "cattle",
                    "breed": "boer",
                    "sex": "male",
                    "age_months": 24,
                    "weight_kg": 100,
                },
                {
                    "livestock_type": "cattle",
                    "breed": "brahman",
                    "sex": "unknown",
                    "age_months": 24,
                    "weight_kg": 100,
                },
                {
                    "livestock_type": "cattle",
                    "breed": "brahman",
                    "sex": "male",
                    "age_months": 0,
                    "weight_kg": 100,
                },
                {
                    "livestock_type": "cattle",
                    "breed": "brahman",
                    "sex": "male",
                    "age_months": 24,
                    "weight_kg": -1,
                },
                {
                    "livestock_type": "cattle",
                    "breed": "brahman",
                    "sex": "male",
                    "age_months": 24,
                    "weight_kg": 100,
                    "extra": True,
                },
            ]
            for payload in cases:
                with self.subTest(payload=payload):
                    response = client.post("/predict", json=payload)
                    body = response.json()
                    self.assertEqual(response.status_code, 422)
                    self.assertEqual(body["status"], "invalid")
                    self.assertIsNone(body["predicted_price_php"])
                    self.assertTrue(body["reason_codes"])

    def test_unexpected_failure_is_generic_500(self):
        with TestClient(create_app()) as client:
            with patch("app.predict", side_effect=RuntimeError("secret internal path")):
                response = client.post(
                    "/predict",
                    json={
                        "livestock_type": "cattle",
                        "breed": "brahman",
                        "sex": "male",
                        "age_months": 48,
                        "weight_kg": 350,
                    },
                )
        body = response.json()
        self.assertEqual(response.status_code, 500)
        self.assertEqual(body["status"], "error")
        self.assertIsNone(body["predicted_price_php"])
        self.assertIn("inference_failure", body["reason_codes"])
        self.assertNotIn("secret", response.text)

    def test_missing_model_fails_readiness_and_prediction(self):
        with TestClient(create_app(model_path=MISSING_PATH)) as client:
            health = client.get("/health")
            ready = client.get("/ready")
            prediction = client.post(
                "/predict",
                json={
                    "livestock_type": "cattle",
                    "breed": "brahman",
                    "sex": "male",
                    "age_months": 48,
                    "weight_kg": 350,
                },
            )
        self.assertEqual(health.status_code, 200)
        self.assertEqual(ready.status_code, 503)
        self.assertEqual(ready.json()["reason_codes"], ["model_unavailable"])
        self.assertEqual(prediction.status_code, 503)
        self.assertIsNone(prediction.json()["predicted_price_php"])
        self.assertNotIn("does-not-exist", prediction.text)
        self.assertNotIn("models", prediction.text)


if __name__ == "__main__":
    unittest.main()
