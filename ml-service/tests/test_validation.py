import tempfile
import unittest
from pathlib import Path

import pandas as pd

from features import TARGET_COLUMN
from validation import (
    build_training_profile,
    load_training_profile,
    out_of_distribution_warnings,
    profile_path,
    save_training_profile,
)


def profile_frame() -> pd.DataFrame:
    return pd.DataFrame(
        [
            {
                "livestock_type": "cattle",
                "breed": "brahman",
                "sex": "male",
                "age_months": 48,
                "weight_kg": 350.0,
                TARGET_COLUMN: 80000.0,
            },
            {
                "livestock_type": "goat",
                "breed": "boer",
                "sex": "female",
                "age_months": 24,
                "weight_kg": 40.0,
                TARGET_COLUMN: 11000.0,
            },
        ]
    )


class TrainingProfileTests(unittest.TestCase):
    def test_builds_ranges_and_observed_combinations(self):
        profile = build_training_profile(
            profile_frame(),
            model_file="model.cbm",
        )

        self.assertEqual(profile["training_rows"], 2)
        self.assertEqual(profile["observed_categories"], ["cattle", "goat"])
        self.assertEqual(profile["observed_breeds"]["cattle"], ["brahman"])
        self.assertEqual(profile["feature_ranges"]["weight_kg"]["min"], 40.0)
        self.assertEqual(profile["feature_ranges"]["weight_kg"]["max"], 350.0)

    def test_sidecar_round_trip(self):
        with tempfile.TemporaryDirectory() as directory:
            model_path = Path(directory) / "model.cbm"
            profile = build_training_profile(
                profile_frame(), model_file=model_path.name
            )
            written = save_training_profile(model_path, profile)

            self.assertEqual(written, profile_path(model_path))
            self.assertTrue(written.is_file())
            self.assertEqual(load_training_profile(model_path), profile)

    def test_missing_profile_returns_none(self):
        with tempfile.TemporaryDirectory() as directory:
            self.assertIsNone(
                load_training_profile(Path(directory) / "missing.cbm")
            )

    def test_warns_outside_numeric_range(self):
        profile = build_training_profile(
            profile_frame(), model_file="model.cbm"
        )
        values = {
            "livestock_type": "cattle",
            "breed": "brahman",
            "sex": "male",
            "age_months": 48,
            "weight_kg": 999,
        }
        warnings = out_of_distribution_warnings(values, profile)

        self.assertTrue(any("weight_kg" in warning for warning in warnings))
        self.assertTrue(any("training range" in warning for warning in warnings))

    def test_does_not_warn_inside_range(self):
        profile = build_training_profile(
            profile_frame(), model_file="model.cbm"
        )
        values = {
            "livestock_type": "goat",
            "breed": "boer",
            "sex": "female",
            "age_months": 24,
            "weight_kg": 40,
        }

        self.assertEqual(out_of_distribution_warnings(values, profile), [])

    def test_warns_for_unobserved_breed(self):
        profile = build_training_profile(
            profile_frame(), model_file="model.cbm"
        )
        values = {
            "livestock_type": "cattle",
            "breed": "brahman_cross",
            "sex": "male",
            "age_months": 48,
            "weight_kg": 350,
        }
        warnings = out_of_distribution_warnings(values, profile)

        self.assertTrue(any("breed" in warning for warning in warnings))

    def test_no_profile_means_no_warnings(self):
        self.assertEqual(
            out_of_distribution_warnings(
                {
                    "livestock_type": "cattle",
                    "breed": "brahman",
                    "sex": "male",
                    "age_months": 48,
                    "weight_kg": 350,
                },
                None,
            ),
            [],
        )


if __name__ == "__main__":
    unittest.main()
