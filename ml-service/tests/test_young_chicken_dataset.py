import unittest

from generate_young_chicken_dataset import (
    AGE_BANDS,
    BREED_ALLOCATION,
    curve_weight_kg,
    generate_rows,
)


class YoungChickenDatasetTests(unittest.TestCase):
    def test_generates_exactly_140_unique_records(self):
        rows = generate_rows(seed=20261105)

        self.assertEqual(len(rows), 140)
        keys = {
            (
                row["livestock_type"],
                row["breed"],
                row["sex"],
                row["age_months"],
                row["weight_kg"],
                row["actual_sale_price"],
            )
            for row in rows
        }
        self.assertEqual(len(keys), 140)

    def test_age_band_and_breed_distribution(self):
        rows = generate_rows(seed=20261105)
        band_counts = {
            band[0]: sum(1 for row in rows if row["age_band"] == band[0])
            for band in AGE_BANDS
        }
        self.assertEqual(band_counts["1-7_days"], 30)
        self.assertEqual(band_counts["8-14_days"], 30)
        self.assertEqual(band_counts["15-21_days"], 40)
        self.assertEqual(band_counts["22-30_days"], 40)

        self.assertEqual(
            set(BREED_ALLOCATION),
            {row["breed"] for row in rows},
        )
        for breed in BREED_ALLOCATION:
            self.assertEqual(
                sum(1 for row in rows if row["breed"] == breed),
                35,
            )

    def test_both_sexes_per_breed_and_fractional_ages(self):
        rows = generate_rows(seed=20261105)
        for breed in BREED_ALLOCATION:
            sexes = {
                row["sex"] for row in rows if row["breed"] == breed
            }
            self.assertEqual(sexes, {"male", "female"})

        self.assertTrue(all(row["age_months"] < 1.0 for row in rows))
        # No generated row should be a whole month.
        self.assertFalse(
            any(
                abs(row["age_months"] - round(row["age_months"])) < 1e-9
                for row in rows
            )
        )

    def test_weights_and_prices_are_positive_and_age_consistent(self):
        rows = generate_rows(seed=20261105)
        for row in rows:
            self.assertGreater(row["weight_kg"], 0)
            price = float(
                row["actual_sale_price"].replace("\u20b1", "").replace(",", "")
            )
            self.assertGreater(price, 0)

        broiler_weights = [
            curve_weight_kg("broiler", day, "male") for day in (1, 7, 14, 30)
        ]
        self.assertEqual(broiler_weights, sorted(broiler_weights))
        self.assertGreater(broiler_weights[-1], broiler_weights[0] * 10)


if __name__ == "__main__":
    unittest.main()
