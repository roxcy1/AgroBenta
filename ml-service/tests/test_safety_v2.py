import unittest

import pandas as pd

from features import TARGET_COLUMN
from validation import (
    APPROVED_WEIGHT_LIMITS,
    GROWTH_WINDOWS,
    assess_safety,
    build_safety_profile,
)


def growth_frame() -> pd.DataFrame:
    rows = []
    for breed in ("brahman", "brahman_cross"):
        for offset in range(40):
            age = 2 + offset
            rows.append(
                {
                    "livestock_type": "cattle",
                    "breed": breed,
                    "sex": "male" if offset % 2 else "female",
                    "age_months": age,
                    "weight_kg": 40.0 + age * 8.0,
                    TARGET_COLUMN: 10000.0 + age * 900.0,
                }
            )
    for offset in range(60):
        age = 1 + offset
        rows.append(
            {
                "livestock_type": "swine",
                "breed": "landrace",
                "sex": "female",
                "age_months": age,
                "weight_kg": 5.0 + age * 3.0,
                TARGET_COLUMN: 2000.0 + age * 500.0,
            }
        )
    for offset in range(50):
        age = 2 + offset
        rows.append(
            {
                "livestock_type": "goat",
                "breed": "boer",
                "sex": "female",
                "age_months": age,
                "weight_kg": 8.0 + age * 1.2,
                TARGET_COLUMN: 3000.0 + age * 200.0,
            }
        )
    return pd.DataFrame(rows)


class SafetySchemaTwoTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.profile = build_safety_profile(
            growth_frame(), model_file="model.cbm"
        )

    def assess(self, category, breed, sex, age, weight):
        return assess_safety(
            {
                "livestock_type": category,
                "breed": breed,
                "sex": sex,
                "age_months": age,
                "weight_kg": weight,
            },
            self.profile,
        )

    def test_profile_is_schema_two_with_new_sections(self):
        self.assertEqual(self.profile["schema_version"], 2)
        self.assertEqual(
            self.profile["approved_weight_limits"]["cattle"],
            list(APPROVED_WEIGHT_LIMITS["cattle"]),
        )
        self.assertEqual(
            len(self.profile["growth_windows"]["swine"]),
            len(GROWTH_WINDOWS["swine"]),
        )
        cattle = self.profile["categories"]["cattle"]
        self.assertIn("p50", cattle["weight_kg"])
        self.assertTrue(cattle["breeds"]["brahman"]["age_bins"])

    def test_withholds_one_month_piglet_at_23kg(self):
        result = self.assess("swine", "landrace", "female", 1, 23)
        self.assertEqual(result.status, "withheld")
        self.assertIn("implausible_age_weight", result.reason_codes)

    def test_withholds_two_month_calf_at_350kg(self):
        result = self.assess("cattle", "brahman", "male", 2, 350)
        self.assertEqual(result.status, "withheld")
        self.assertIn("implausible_age_weight", result.reason_codes)

    def test_withholds_three_month_piglet_at_60kg(self):
        result = self.assess("swine", "landrace", "female", 3, 60)
        self.assertEqual(result.status, "withheld")
        self.assertIn("implausible_age_weight", result.reason_codes)

    def test_keeps_three_month_piglet_at_45kg(self):
        result = self.assess("swine", "landrace", "female", 3, 45)
        self.assertNotEqual(result.status, "withheld")

    def test_keeps_legitimate_young_animals(self):
        for category, breed, sex, age, weight in (
            ("cattle", "brahman", "male", 3, 70),
            ("swine", "landrace", "female", 1, 10),
            ("goat", "boer", "female", 3, 12),
        ):
            with self.subTest(category=category, age=age):
                result = self.assess(category, breed, sex, age, weight)
                self.assertNotEqual(result.status, "withheld")

    def test_allows_approved_minimum_outside_training_support(self):
        result = self.assess("goat", "boer", "female", 2, 10.0)
        self.assertEqual(result.status, "warning")
        self.assertIn("outside_training_support", result.reason_codes)
        self.assertIn("outside_typical_weight", result.reason_codes)

    def test_rejects_weight_above_the_approved_maximum(self):
        result = self.assess("cattle", "brahman", "male", 24, 500)
        self.assertEqual(result.status, "withheld")
        self.assertEqual(result.reason_codes, ("outside_supported_weight",))

    def test_rejects_weight_below_the_approved_minimum(self):
        result = self.assess("cattle", "brahman", "male", 3, 40)
        self.assertEqual(result.status, "withheld")
        self.assertIn("outside_supported_weight", result.reason_codes)

    def test_age_aware_breed_warning_fires_for_a_starved_animal(self):
        result = self.assess("cattle", "brahman", "male", 24, 120)
        self.assertNotEqual(result.status, "withheld")
        self.assertIn("outside_typical_breed_weight", result.reason_codes)

    def test_legacy_schema_one_keeps_support_margin_behaviour(self):
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


if __name__ == "__main__":
    unittest.main()
