import unittest

import pandas as pd

from generate_young_chicken_dataset import AGE_BANDS, generate_rows
from train import feature_group_keys
from train_young_chicken import (
    _recommendation,
    age_band,
    split_young_chickens,
)


def young_frame() -> pd.DataFrame:
    rows = generate_rows(seed=20261105)
    return pd.DataFrame(rows)[
        [
            "livestock_type",
            "breed",
            "sex",
            "age_months",
            "weight_kg",
            "actual_sale_price",
        ]
    ]


class YoungChickenSplitTests(unittest.TestCase):
    def test_age_band_mapping(self):
        self.assertEqual(age_band(1 / 30.4375), "1-7_days")
        self.assertEqual(age_band(30 / 30.4375), "22-30_days")
        self.assertIsNone(age_band(1.0))

    def test_split_is_40_rows_and_covers_every_band(self):
        train, test, _seed = split_young_chickens(young_frame())

        self.assertEqual(len(train), 100)
        self.assertEqual(len(test), 40)
        self.assertEqual(
            set(test["age_months"].map(age_band)),
            {band[0] for band in AGE_BANDS},
        )
        self.assertFalse(
            set(feature_group_keys(train)) & set(feature_group_keys(test))
        )


class RecommendationTests(unittest.TestCase):
    def _args(self, young_improvement: float, original_change: float, category_change: float):
        young_v1 = {"mae": 100.0, "rmse": 120.0, "mape_percent": 20.0}
        young_candidate = {
            "mae": young_v1["mae"] * (1 - young_improvement / 100),
            "rmse": 100.0,
            "mape_percent": 10.0,
        }
        original_v1 = {"mae": 1000.0, "rmse": 1200.0, "mape_percent": 10.0}
        original_candidate = {
            "mae": original_v1["mae"] * (1 + original_change / 100),
            "rmse": 1201.0,
            "mape_percent": 10.0,
        }
        category_comparison = {
            "chicken": {
                "candidate": {"mae": 100.0 * (1 + category_change / 100)},
                "v1": {"mae": 100.0},
            }
        }
        return (
            original_v1,
            original_candidate,
            young_v1,
            young_candidate,
            category_comparison,
        )

    def test_considers_v2_when_young_chicken_improves_without_regression(self):
        result = _recommendation(*self._args(30.0, 1.0, 2.0))
        self.assertTrue(result["consider_v2"])

    def test_retains_v1_when_original_test_regresses(self):
        result = _recommendation(*self._args(30.0, 3.0, 2.0))
        self.assertFalse(result["consider_v2"])

    def test_retains_v1_when_young_improvement_is_too_small(self):
        result = _recommendation(*self._args(10.0, 0.5, 1.0))
        self.assertFalse(result["consider_v2"])


if __name__ == "__main__":
    unittest.main()
