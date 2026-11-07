import unittest

import numpy as np
import pandas as pd

from tune_targeted_v3 import (
    acceptance,
    sample_training_frame,
    sample_weights,
    selection_decision,
)


def weighting_frame() -> pd.DataFrame:
    rows = []
    for index in range(20):
        rows.append(
            {
                "livestock_type": "chicken",
                "breed": "broiler",
                "sex": "male",
                "age_months": 0.1 if index < 10 else 12,
                "weight_kg": 0.2 if index < 10 else 2.0,
                "actual_sale_price": 50.0 if index < 10 else 400.0,
            }
        )
    for index in range(40):
        rows.append(
            {
                "livestock_type": "goat",
                "breed": "boer",
                "sex": "female",
                "age_months": 12,
                "weight_kg": 40.0,
                "actual_sale_price": 12000.0,
            }
        )
    return pd.DataFrame(rows)


class WeightStrategyTests(unittest.TestCase):
    def test_young_and_older_weights(self):
        frame = weighting_frame()
        weights = sample_weights(frame, "young_0.25_older_1.5")

        self.assertEqual(int((weights == 0.25).sum()), 10)
        self.assertEqual(int((weights == 1.5).sum()), 10)
        self.assertEqual(int((weights == 1.0).sum()), 40)

        balanced = sample_weights(frame, "older_2.0_young_1.05")
        self.assertEqual(int((balanced == 2.0).sum()), 10)
        self.assertEqual(int((balanced == 1.05).sum()), 10)
        self.assertEqual(int((balanced == 1.0).sum()), 40)

    def test_undersampling_keeps_all_non_young_rows(self):
        rows = []
        for index in range(100):
            rows.append(
                {
                    "livestock_type": "chicken",
                    "breed": "broiler",
                    "sex": "male",
                    "age_months": 0.1 + index * 0.001,
                    "weight_kg": 0.2,
                    "actual_sale_price": 50.0,
                }
            )
        for index in range(10):
            rows.append(
                {
                    "livestock_type": "chicken",
                    "breed": "broiler",
                    "sex": "male",
                    "age_months": 12.0 + index,
                    "weight_kg": 2.0,
                    "actual_sale_price": 400.0,
                }
            )
        for index in range(40):
            rows.append(
                {
                    "livestock_type": "goat",
                    "breed": "boer",
                    "sex": "female",
                    "age_months": 12,
                    "weight_kg": 40.0,
                    "actual_sale_price": 12000.0,
                }
            )
        frame = pd.DataFrame(rows)
        sampled = sample_training_frame(frame, "young_50", seed=1)

        young = (sampled["livestock_type"] == "chicken") & (
            sampled["age_months"] < 1.0
        )
        older = (sampled["livestock_type"] == "chicken") & (
            sampled["age_months"] >= 1.0
        )
        self.assertEqual(int(young.sum()), 50)
        self.assertEqual(int(older.sum()), 10)
        self.assertEqual(
            int((sampled["livestock_type"] != "chicken").sum()), 40
        )


def trial(trial_id: str, older: float, young: float, overall: float, category: float):
    return {
        "id": trial_id,
        "validation": {
            "overall": {"mae": overall, "rmse": overall, "mape_percent": 10},
            "older_chicken": {"mae": older},
            "young_chicken": {"mae": young},
            "per_category": {
                "cattle": {"mae": category},
                "goat": {"mae": category},
            },
        },
    }


class SelectionTests(unittest.TestCase):
    def test_selects_lowest_older_mae_under_guardrails(self):
        reference = trial("reference", 50.0, 6.0, 100.0, 100.0)
        eligible = trial("eligible", 45.0, 6.5, 101.0, 101.0)
        ineligible = trial("ineligible", 40.0, 8.0, 100.0, 100.0)

        result = selection_decision(reference, [reference, eligible, ineligible])

        self.assertEqual(result["selected_trial_id"], "eligible")
        self.assertTrue(result["selection_eligible"])

    def test_falls_back_to_lowest_older_mae_when_none_eligible(self):
        reference = trial("reference", 50.0, 6.0, 100.0, 100.0)
        ineligible = trial("ineligible", 40.0, 8.0, 100.0, 100.0)

        result = selection_decision(reference, [reference, ineligible])

        self.assertEqual(result["selected_trial_id"], "reference")
        self.assertFalse(result["selection_eligible"])


class AcceptanceTests(unittest.TestCase):
    def _candidate(self, older, young, category_mae):
        return (
            {
                "overall": {"mae": 2900.0},
                "by_category": {
                    "chicken": {"mae": older},
                    "cattle": {"mae": category_mae},
                    "carabao": {"mae": category_mae},
                    "goat": {"mae": category_mae},
                    "swine": {"mae": category_mae},
                },
            },
            {"overall": {"mae": young}},
        )

    def test_accepts_when_all_targets_pass(self):
        original, young = self._candidate(47.0, 6.5, 100.0)
        per_category = original["by_category"]
        v2 = {
            "cattle": {"mae": 100.0},
            "carabao": {"mae": 100.0},
            "goat": {"mae": 100.0},
            "swine": {"mae": 100.0},
        }
        result = acceptance(original, young, per_category, v2)
        self.assertTrue(result["accepted"])

    def test_rejects_when_older_chicken_misses_target(self):
        original, young = self._candidate(49.0, 6.5, 100.0)
        per_category = original["by_category"]
        v2 = {
            "cattle": {"mae": 100.0},
            "carabao": {"mae": 100.0},
            "goat": {"mae": 100.0},
            "swine": {"mae": 100.0},
        }
        result = acceptance(original, young, per_category, v2)
        self.assertFalse(result["older_chicken_pass"])
        self.assertFalse(result["accepted"])

    def test_rejects_when_non_chicken_category_regresses(self):
        original, young = self._candidate(47.0, 6.5, 106.0)
        per_category = original["by_category"]
        v2 = {
            "cattle": {"mae": 100.0},
            "carabao": {"mae": 100.0},
            "goat": {"mae": 100.0},
            "swine": {"mae": 100.0},
        }
        result = acceptance(original, young, per_category, v2)
        self.assertFalse(result["non_chicken_pass"])
        self.assertFalse(result["accepted"])


if __name__ == "__main__":
    unittest.main()
