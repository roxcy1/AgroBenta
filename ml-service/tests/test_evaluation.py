import unittest

import numpy as np
import pandas as pd

from features import TARGET_COLUMN
from improve import decision, select_best_trial
from train import per_category_metrics, regression_metrics


class MetricTests(unittest.TestCase):
    def test_regression_metrics(self):
        metrics = regression_metrics([100.0, 200.0], [110.0, 180.0])

        self.assertAlmostEqual(metrics["mae"], 15.0)
        self.assertAlmostEqual(metrics["rmse"], 15.8114, places=4)
        self.assertAlmostEqual(metrics["mape_percent"], 10.0, places=4)

    def test_per_category_metrics(self):
        frame = pd.DataFrame(
            [
                {"livestock_type": "cattle", TARGET_COLUMN: 100.0},
                {"livestock_type": "cattle", TARGET_COLUMN: 200.0},
                {"livestock_type": "goat", TARGET_COLUMN: 50.0},
            ]
        )
        predictions = np.array([110.0, 180.0, 45.0])

        metrics = per_category_metrics(frame, predictions)

        self.assertEqual(metrics["cattle"]["n"], 2)
        self.assertAlmostEqual(metrics["cattle"]["mae"], 15.0)
        self.assertEqual(metrics["goat"]["n"], 1)
        self.assertAlmostEqual(metrics["goat"]["mae"], 5.0)


class SelectionTests(unittest.TestCase):
    def test_selects_lowest_validation_mae_then_mape(self):
        trials = [
            {
                "id": "a",
                "validation": {
                    "overall": {"mae": 10.0, "rmse": 20.0, "mape_percent": 5.0}
                },
            },
            {
                "id": "b",
                "validation": {
                    "overall": {"mae": 9.0, "rmse": 30.0, "mape_percent": 8.0}
                },
            },
            {
                "id": "c",
                "validation": {
                    "overall": {"mae": 9.0, "rmse": 25.0, "mape_percent": 7.0}
                },
            },
        ]

        self.assertEqual(select_best_trial(trials)["id"], "c")

    def _decision_args(self, candidate_mae, candidate_mape):
        v1 = {"mae": 100.0, "rmse": 200.0, "mape_percent": 10.0}
        candidate = {
            "mae": candidate_mae,
            "rmse": 210.0,
            "mape_percent": candidate_mape,
        }
        v1_per_category = {
            "cattle": {"mae": 100.0},
            "goat": {"mae": 100.0},
        }
        candidate_per_category = {
            "cattle": {"mae": 105.0},
            "goat": {"mae": 95.0},
        }
        return v1, candidate, v1_per_category, candidate_per_category

    def test_saves_when_mae_improves_and_mape_does_not_worsen(self):
        verdict = decision(*self._decision_args(90.0, 10.0))

        self.assertTrue(verdict["save_improved_model"])

    def test_retains_when_mae_improvement_is_below_one_percent(self):
        verdict = decision(*self._decision_args(99.5, 10.0))

        self.assertFalse(verdict["save_improved_model"])

    def test_retains_when_mape_worsens(self):
        verdict = decision(*self._decision_args(90.0, 11.0))

        self.assertFalse(verdict["save_improved_model"])


if __name__ == "__main__":
    unittest.main()
