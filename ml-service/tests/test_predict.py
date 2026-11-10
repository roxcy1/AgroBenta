import tempfile
import unittest
from pathlib import Path

import pandas as pd
from catboost import CatBoostRegressor

from features import CATEGORICAL_FEATURES, FEATURE_COLUMNS, TARGET_COLUMN
from predict import (
    UnsafePredictionError,
    latest_model_path,
    load_model,
    predict,
    predict_price,
)
from validation import (
    build_safety_profile,
    build_training_profile,
    save_safety_profile,
    save_training_profile,
)


def training_frame() -> pd.DataFrame:
    rows = []
    for index in range(16):
        category = "cattle" if index % 2 == 0 else "goat"
        breed = "brahman" if category == "cattle" else "boer"
        rows.append(
            {
                "livestock_type": category,
                "breed": breed,
                "sex": "male" if index % 3 else "female",
                "age_months": 12 + index,
                "weight_kg": 150.0 + index * 12,
                TARGET_COLUMN: 50000.0 + index * 2500,
            }
        )
    return pd.DataFrame(rows)


class PredictionTests(unittest.TestCase):
    def _trained_model(
        self, directory: str
    ) -> tuple[pd.DataFrame, CatBoostRegressor, Path]:
        frame = training_frame()
        model = CatBoostRegressor(
            iterations=10,
            depth=2,
            learning_rate=0.1,
            random_seed=1,
            verbose=False,
            allow_writing_files=False,
            thread_count=1,
        )
        model.fit(
            frame.loc[:, list(FEATURE_COLUMNS)],
            frame[TARGET_COLUMN],
            cat_features=list(CATEGORICAL_FEATURES),
            verbose=False,
        )
        path = Path(directory) / "catboost_price_v1_test.cbm"
        model.save_model(str(path))
        save_training_profile(
            path,
            build_training_profile(frame, model_file=path.name),
        )
        save_safety_profile(
            path,
            build_safety_profile(frame, model_file=path.name),
        )
        return frame, model, path

    def test_loads_saved_model_without_retraining_and_predicts(self):
        with tempfile.TemporaryDirectory() as directory:
            _, _, path = self._trained_model(directory)
            loaded, loaded_path = load_model(path, allow_unregistered=True)

            self.assertEqual(loaded_path, path)
            result = predict(
                livestock_type="cattle",
                breed="brahman",
                sex="male",
                age_months=20,
                weight_kg=246,
                model=loaded,
                model_path=path,
            )

        self.assertNotEqual(result.status, "withheld")
        self.assertIsNotNone(result.price)
        self.assertGreater(result.price, 0)
        self.assertEqual(result.provenance, "unknown")
        self.assertEqual(result.model_version, "unregistered")

    def test_predict_price_raises_when_withheld(self):
        with tempfile.TemporaryDirectory() as directory:
            _, model, path = self._trained_model(directory)
            with self.assertRaises(UnsafePredictionError):
                predict_price(
                    livestock_type="cattle",
                    breed="brahman",
                    sex="male",
                    age_months=20,
                    weight_kg=9999,
                    model=model,
                    model_path=path,
                )

    def test_prediction_withholds_when_input_is_outside_supported_range(self):
        with tempfile.TemporaryDirectory() as directory:
            _, model, path = self._trained_model(directory)
            result = predict(
                livestock_type="cattle",
                breed="brahman",
                sex="male",
                age_months=20,
                weight_kg=9999,
                model=model,
                model_path=path,
            )

        self.assertEqual(result.status, "withheld")
        self.assertIsNone(result.price)
        self.assertIn("outside_supported_weight", result.reason_codes)

    def test_prediction_warns_for_typical_range_excursion(self):
        with tempfile.TemporaryDirectory() as directory:
            frame, model, path = self._trained_model(directory)
            safety = build_safety_profile(frame, model_file=path.name)
            category = safety["categories"]["cattle"]
            category["weight_kg"] = {
                "min": 150.0,
                "max": 1000.0,
                "p01": 150.0,
                "p99": 300.0,
            }
            category["breeds"]["brahman"]["weight_kg"] = {
                "min": 150.0,
                "max": 1000.0,
                "p01": 150.0,
                "p99": 300.0,
            }
            for age_bin in category["age_bins"]:
                age_bin["weight_kg"] = {
                    "min": 150.0,
                    "max": 1000.0,
                    "p01": 150.0,
                    "p99": 300.0,
                }
            save_safety_profile(path, safety)

            result = predict(
                livestock_type="cattle",
                breed="brahman",
                sex="male",
                age_months=20,
                weight_kg=500,
                model=model,
                model_path=path,
            )

        self.assertEqual(result.status, "warning")
        self.assertIsNotNone(result.price)
        self.assertIn("outside_typical_weight", result.reason_codes)

    def test_rejects_unsupported_combination_before_loading(self):
        with self.assertRaises(ValueError):
            predict_price(
                livestock_type="cattle",
                breed="boer",
                sex="male",
                age_months=20,
                weight_kg=250,
            )

    def test_rejects_invalid_values_before_loading(self):
        for age, weight, sex in ((0, 250, "male"), (20, 0, "male"), (20, 250, "x")):
            with self.subTest(age=age, weight=weight, sex=sex):
                with self.assertRaises(ValueError):
                    predict_price(
                        livestock_type="cattle",
                        breed="brahman",
                        sex=sex,
                        age_months=age,
                        weight_kg=weight,
                    )

    def test_missing_model_is_reported(self):
        with tempfile.TemporaryDirectory() as directory:
            missing = Path(directory) / "missing.cbm"
            with self.assertRaises(FileNotFoundError):
                load_model(missing)

    def test_latest_model_requires_a_saved_model(self):
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaises(FileNotFoundError):
                latest_model_path(Path(directory))


if __name__ == "__main__":
    unittest.main()
