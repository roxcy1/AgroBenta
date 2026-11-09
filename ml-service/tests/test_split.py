import unittest

import pandas as pd

from features import FEATURE_COLUMNS, TARGET_COLUMN
from train import assign_split, feature_group_keys, split_summary


def sample_frame() -> pd.DataFrame:
    rows = []
    for category, breed in (("cattle", "brahman"), ("goat", "boer")):
        for index in range(20):
            rows.append(
                {
                    "livestock_type": category,
                    "breed": breed,
                    "sex": "male" if index % 2 == 0 else "female",
                    "age_months": index + 1,
                    "weight_kg": 100.0 + index * 10,
                    TARGET_COLUMN: 50000.0 + index * 1000,
                }
            )
        # Repeated feature combination: must stay in one split.
        rows.append(dict(rows[-20]))
        rows.append(dict(rows[-20]))

    return pd.DataFrame(rows, columns=list(FEATURE_COLUMNS) + [TARGET_COLUMN])


class LeakageSafeSplitTests(unittest.TestCase):
    def test_no_feature_group_crosses_the_split(self):
        frame = sample_frame()
        train, test = assign_split(frame, test_fraction=0.2, seed=42)

        train_keys = set(feature_group_keys(train))
        test_keys = set(feature_group_keys(test))

        self.assertFalse(train_keys & test_keys)
        self.assertTrue(len(train) > 0)
        self.assertTrue(len(test) > 0)

    def test_all_categories_are_held_out(self):
        frame = sample_frame()
        train, test = assign_split(frame, test_fraction=0.2, seed=42)
        summary = split_summary(
            frame,
            train,
            test,
            test_fraction=0.2,
            seed=42,
        )

        self.assertEqual(summary["feature_groups_in_both_splits"], 0)
        self.assertEqual(summary["missing_categories"], [])
        self.assertEqual(
            set(summary["held_out_categories"]),
            set(frame["livestock_type"].unique()),
        )

    def test_split_is_reproducible(self):
        frame = sample_frame()
        train_a, test_a = assign_split(frame, test_fraction=0.2, seed=7)
        train_b, test_b = assign_split(frame, test_fraction=0.2, seed=7)

        pd.testing.assert_frame_equal(train_a, train_b)
        pd.testing.assert_frame_equal(test_a, test_b)

    def test_rejects_invalid_fraction(self):
        frame = sample_frame()
        for fraction in (0, 1, -0.1, 1.1):
            with self.subTest(fraction=fraction):
                with self.assertRaises(ValueError):
                    assign_split(frame, test_fraction=fraction, seed=42)


if __name__ == "__main__":
    unittest.main()
