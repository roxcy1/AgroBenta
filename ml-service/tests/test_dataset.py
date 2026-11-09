import csv
import tempfile
import unittest
from pathlib import Path

from features import DatasetValidationError
from train import load_and_validate_dataset


HEADER = [
    "livestock_type",
    "breed",
    "sex",
    "age_months",
    "weight_kg",
    "actual_sale_price",
]


class DatasetLoadingTests(unittest.TestCase):
    def _write(self, directory: str, rows: list[list[object]], header=HEADER) -> Path:
        path = Path(directory) / "dataset.csv"
        with path.open("w", encoding="utf-8", newline="") as handle:
            writer = csv.writer(handle)
            writer.writerow(header)
            writer.writerows(rows)
        return path

    def test_loads_parses_and_removes_exact_duplicates(self):
        duplicates = [
            ["cattle", "brahman", "male", 48, 350.5, "\u20b1124,090"],
            ["cattle", "brahman", "male", 48, 350.5, "\u20b1124,090"],
        ]
        different_price = [
            ["goat", "boer", "female", 24, 40.0, "\u20b111,000"],
            ["goat", "boer", "female", 24, 40.0, "\u20b111,500"],
        ]

        with tempfile.TemporaryDirectory() as directory:
            path = self._write(directory, duplicates + different_price)
            frame, summary = load_and_validate_dataset(path)

        self.assertEqual(summary["rows_loaded"], 4)
        self.assertEqual(summary["rows_after_exact_duplicate_removal"], 3)
        self.assertEqual(summary["exact_duplicates_removed"], 1)
        self.assertEqual(summary["feature_duplicate_rows"], 1)
        self.assertEqual(summary["feature_groups_with_conflicting_prices"], 1)
        self.assertEqual(summary["counts_by_category"]["cattle"], 1)
        self.assertEqual(summary["counts_by_category"]["goat"], 2)
        self.assertEqual(len(frame), 3)
        self.assertEqual(frame["actual_sale_price"].dtype.kind, "f")

    def test_rejects_missing_required_column(self):
        with tempfile.TemporaryDirectory() as directory:
            path = self._write(
                directory,
                [["cattle", "brahman", "male", 48, 350.5, "\u20b1124,090"]],
                header=[column for column in HEADER if column != "sex"],
            )
            with self.assertRaises(DatasetValidationError):
                load_and_validate_dataset(path)

    def test_rejects_invalid_sex(self):
        with tempfile.TemporaryDirectory() as directory:
            path = self._write(
                directory,
                [["cattle", "brahman", "unknown", 48, 350.5, "\u20b1124,090"]],
            )
            with self.assertRaises(DatasetValidationError):
                load_and_validate_dataset(path)

    def test_rejects_invalid_numeric_range(self):
        with tempfile.TemporaryDirectory() as directory:
            path = self._write(
                directory,
                [["cattle", "brahman", "male", 0, 350.5, "\u20b1124,090"]],
            )
            with self.assertRaises(DatasetValidationError):
                load_and_validate_dataset(path)

    def test_rejects_unsupported_breed_for_category(self):
        with tempfile.TemporaryDirectory() as directory:
            path = self._write(
                directory,
                [["cattle", "boer", "male", 48, 350.5, "\u20b1124,090"]],
            )
            with self.assertRaises(DatasetValidationError):
                load_and_validate_dataset(path)

    def test_rejects_unparseable_price(self):
        with tempfile.TemporaryDirectory() as directory:
            path = self._write(
                directory,
                [["cattle", "brahman", "male", 48, 350.5, "not a price"]],
            )
            with self.assertRaises(DatasetValidationError):
                load_and_validate_dataset(path)


if __name__ == "__main__":
    unittest.main()
