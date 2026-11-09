import unittest

import pandas as pd

from features import TARGET_COLUMN
from validation import assess_safety, build_safety_profile


def training_frame() -> pd.DataFrame:
    rows = []
    for index in range(20):
        rows.append(
            {
                "livestock_type": "cattle",
                "breed": "brahman",
                "sex": "male",
                "age_months": 12 + index,
                "weight_kg": 200.0 + index * 10,
                TARGET_COLUMN: 50000.0 + index * 1000,
            }
        )
    for index in range(20):
        rows.append(
            {
                "livestock_type": "chicken",
                "breed": "broiler",
                "sex": "male",
                "age_months": 0.1 + index * 0.04,
                "weight_kg": 0.1 + index * 0.02,
                TARGET_COLUMN: 40.0 + index * 5,
            }
        )
    return pd.DataFrame(rows)


def young_chicken_profile() -> dict:
    return {
        "categories": {
            "chicken": {
                "age_months": {
                    "min": 0.032854,
                    "max": 30,
                    "p01": 0.065708,
                    "p99": 29,
                },
                "weight_kg": {
                    "min": 0.03,
                    "max": 4.0,
                    "p01": 0.05,
                    "p99": 3.5084,
                },
                "breeds": {
                    "broiler": {
                        "age_months": {
                            "min": 0.032854,
                            "max": 30,
                            "p01": 0.065708,
                            "p99": 29,
                        },
                        "weight_kg": {
                            "min": 0.03,
                            "max": 4.0,
                            "p01": 0.05,
                            "p99": 3.5084,
                        },
                    }
                },
                "age_bins": [
                    {
                        "min": 0.032854,
                        "max": 0.821355,
                        "max_inclusive": False,
                        "weight_kg": {
                            "min": 0.03,
                            "max": 1.04,
                            "p01": 0.0381,
                            "p99": 0.9428,
                        },
                    },
                    {
                        "min": 1.0,
                        "max": 3.0,
                        "max_inclusive": False,
                        "weight_kg": {
                            "min": 0.91,
                            "max": 2.0,
                            "p01": 0.9192,
                            "p99": 1.9908,
                        },
                    },
                ],
            }
        }
    }


class SafetyAssessmentTests(unittest.TestCase):
    def setUp(self):
        self.profile = build_safety_profile(
            training_frame(), model_file="model.cbm"
        )

    def test_accepts_normal_input(self):
        result = assess_safety(
            {
                "livestock_type": "cattle",
                "breed": "brahman",
                "sex": "male",
                "age_months": 20,
                "weight_kg": 300,
            },
            self.profile,
        )
        self.assertEqual(result.status, "ok")
        self.assertEqual(result.reason_codes, ())

    def test_withholds_impossible_chicken_weight(self):
        result = assess_safety(
            {
                "livestock_type": "chicken",
                "breed": "broiler",
                "sex": "male",
                "age_months": 0.1,
                "weight_kg": 500,
            },
            self.profile,
        )
        self.assertEqual(result.status, "withheld")
        self.assertIn("outside_supported_weight", result.reason_codes)

    def test_withholds_age_outside_supported_envelope(self):
        result = assess_safety(
            {
                "livestock_type": "cattle",
                "breed": "brahman",
                "sex": "male",
                "age_months": 1,
                "weight_kg": 300,
            },
            self.profile,
        )
        self.assertEqual(result.status, "withheld")
        self.assertIn("outside_supported_age", result.reason_codes)

    def test_withholds_joint_age_weight_mismatch(self):
        profile = {
            "categories": {
                "cattle": {
                    "age_months": {"min": 1, "max": 100, "p01": 1, "p99": 100},
                    "weight_kg": {
                        "min": 1,
                        "max": 1000,
                        "p01": 1,
                        "p99": 1000,
                    },
                    "breeds": {
                        "brahman": {
                            "age_months": {
                                "min": 1,
                                "max": 100,
                                "p01": 1,
                                "p99": 100,
                            },
                            "weight_kg": {
                                "min": 1,
                                "max": 1000,
                                "p01": 1,
                                "p99": 1000,
                            },
                        }
                    },
                    "age_bins": [
                        {
                            "min": 1,
                            "max": 100,
                            "max_inclusive": True,
                            "weight_kg": {
                                "min": 100,
                                "max": 200,
                                "p01": 100,
                                "p99": 200,
                            },
                        }
                    ],
                }
            }
        }
        result = assess_safety(
            {
                "livestock_type": "cattle",
                "breed": "brahman",
                "sex": "male",
                "age_months": 20,
                "weight_kg": 500,
            },
            profile,
        )
        self.assertEqual(result.status, "withheld")
        self.assertIn("insufficient_model_support", result.reason_codes)

    def test_fifteen_day_broiler_at_half_kg_is_not_withheld(self):
        result = assess_safety(
            {
                "livestock_type": "chicken",
                "breed": "broiler",
                "sex": "male",
                "age_months": 15 / 30.4375,
                "weight_kg": 0.5,
            },
            young_chicken_profile(),
        )
        self.assertNotEqual(result.status, "withheld")

    def test_one_month_broiler_at_half_kg_is_warning_not_withheld(self):
        result = assess_safety(
            {
                "livestock_type": "chicken",
                "breed": "broiler",
                "sex": "male",
                "age_months": 1.0,
                "weight_kg": 0.5,
            },
            young_chicken_profile(),
        )
        self.assertEqual(result.status, "warning")
        self.assertNotIn("insufficient_model_support", result.reason_codes)

    def test_three_day_heavy_chicken_is_withheld(self):
        result = assess_safety(
            {
                "livestock_type": "chicken",
                "breed": "broiler",
                "sex": "male",
                "age_months": 3 / 30.4375,
                "weight_kg": 4.0,
            },
            young_chicken_profile(),
        )
        self.assertEqual(result.status, "withheld")
        self.assertIn("insufficient_model_support", result.reason_codes)

    def test_three_day_500kg_chicken_is_withheld(self):
        result = assess_safety(
            {
                "livestock_type": "chicken",
                "breed": "broiler",
                "sex": "male",
                "age_months": 3 / 30.4375,
                "weight_kg": 500,
            },
            young_chicken_profile(),
        )
        self.assertEqual(result.status, "withheld")
        self.assertIn("outside_supported_weight", result.reason_codes)

    def test_warns_for_typical_range_excursion(self):
        profile = {
            "categories": {
                "cattle": {
                    "age_months": {"min": 1, "max": 100, "p01": 1, "p99": 100},
                    "weight_kg": {
                        "min": 1,
                        "max": 1000,
                        "p01": 1,
                        "p99": 300,
                    },
                    "breeds": {
                        "brahman": {
                            "age_months": {
                                "min": 1,
                                "max": 100,
                                "p01": 1,
                                "p99": 100,
                            },
                            "weight_kg": {
                                "min": 1,
                                "max": 1000,
                                "p01": 1,
                                "p99": 300,
                            },
                        }
                    },
                    "age_bins": [
                        {
                            "min": 1,
                            "max": 100,
                            "max_inclusive": True,
                            "weight_kg": {
                                "min": 1,
                                "max": 1000,
                                "p01": 1,
                                "p99": 300,
                            },
                        }
                    ],
                }
            }
        }
        result = assess_safety(
            {
                "livestock_type": "cattle",
                "breed": "brahman",
                "sex": "male",
                "age_months": 20,
                "weight_kg": 500,
            },
            profile,
        )
        self.assertEqual(result.status, "warning")
        self.assertIn("outside_typical_weight", result.reason_codes)

    def test_missing_profile_fails_closed(self):
        result = assess_safety(
            {
                "livestock_type": "cattle",
                "breed": "brahman",
                "sex": "male",
                "age_months": 20,
                "weight_kg": 300,
            },
            None,
        )
        self.assertEqual(result.status, "withheld")
        self.assertIn("missing_safety_profile", result.reason_codes)


if __name__ == "__main__":
    unittest.main()
