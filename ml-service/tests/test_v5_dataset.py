import csv
import tempfile
import unittest
from collections import Counter
from pathlib import Path
from unittest import mock

import pandas as pd

import evaluate_candidate
import train_candidate
from build_v5_dataset import (
    APPROVED_WEIGHT_LIMITS,
    BREED_MAP,
    EFFECTIVE_BREEDS,
    OUTPUT_PATH,
    SOURCE_PATH,
)
from features import REQUIRED_COLUMNS, SUPPORTED_BREEDS, DatasetValidationError
from train import infer_provenance, load_and_validate_dataset
from train_candidate import (
    DEFAULT_DATASET,
    EXPECTED_PER_BREED,
    EXPECTED_ROWS,
    _expected_audit,
    split_frames,
)

BASE_DIR = Path(__file__).resolve().parent.parent


class V5DatasetTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        assert OUTPUT_PATH.is_file(), "Run build_v5_dataset.py first."
        cls.frame, cls.summary = load_and_validate_dataset(OUTPUT_PATH)

    def test_source_is_preserved_and_separate_from_the_output(self):
        self.assertTrue(SOURCE_PATH.is_file())
        self.assertNotEqual(SOURCE_PATH, OUTPUT_PATH)
        self.assertEqual(
            OUTPUT_PATH.relative_to(BASE_DIR).as_posix(),
            "data/livestock_sales_v5_synthetic.csv",
        )
        self.assertEqual(
            DEFAULT_DATASET.relative_to(BASE_DIR).as_posix(),
            "data/livestock_sales_v5_synthetic.csv",
        )

    def test_loads_exactly_4000_rows_and_six_columns(self):
        self.assertEqual(len(self.frame), EXPECTED_ROWS)
        self.assertEqual(list(self.frame.columns), list(REQUIRED_COLUMNS))
        self.assertEqual(self.summary["exact_duplicates_removed"], 0)
        self.assertEqual(
            self.summary["rows_after_exact_duplicate_removal"], EXPECTED_ROWS
        )

    def test_uses_only_the_20_existing_canonical_breeds_at_200_each(self):
        counts = Counter(
            (str(category), str(breed))
            for category, breed in self.frame[
                ["livestock_type", "breed"]
            ].itertuples(index=False, name=None)
        )
        self.assertEqual(set(counts), EFFECTIVE_BREEDS)
        self.assertEqual(len(counts), 20)
        for pair, count in counts.items():
            self.assertEqual(count, EXPECTED_PER_BREED, pair)

    def test_breed_labels_are_lowercase_slugs(self):
        for breed in self.frame["breed"].unique():
            self.assertEqual(breed, breed.lower())
            self.assertNotIn(" ", breed)
            self.assertNotIn("-", breed)
            self.assertNotIn("/", breed)
            self.assertNotIn("(", breed)

    def test_no_missing_or_invalid_values(self):
        self.assertFalse(self.frame.isna().any().any())
        self.assertTrue(
            set(self.frame["livestock_type"]).issubset(SUPPORTED_BREEDS)
        )
        self.assertTrue(set(self.frame["sex"]).issubset({"male", "female"}))
        self.assertTrue((self.frame["age_months"] > 0).all())
        self.assertTrue((self.frame["weight_kg"] > 0).all())
        self.assertTrue((self.frame["actual_sale_price"] > 0).all())

    def test_weights_stay_inside_the_approved_ranges(self):
        for category, (low, high) in APPROVED_WEIGHT_LIMITS.items():
            weights = self.frame.loc[
                self.frame["livestock_type"] == category, "weight_kg"
            ]
            self.assertGreaterEqual(weights.min(), low)
            self.assertLessEqual(weights.max(), high)

    def test_expected_audit_accepts_v5_and_rejects_a_v4_shape(self):
        audit = _expected_audit(self.frame)
        self.assertEqual(audit["rows"], EXPECTED_ROWS)
        with self.assertRaises(DatasetValidationError):
            _expected_audit(self.frame, expected_rows=3000, expected_per_breed=150)

    def test_split_is_group_safe_reproducible_and_70_15_15(self):
        first = split_frames(self.frame)
        second = split_frames(self.frame)
        train_a, validation_a, test_a, split = first
        train_b, validation_b, test_b, _ = second

        self.assertEqual(
            split["rows"], {"train": 2800, "validation": 600, "test": 600}
        )
        self.assertEqual(
            list(train_a.index), list(train_b.index)
        )
        self.assertEqual(
            list(validation_a.index), list(validation_b.index)
        )
        self.assertEqual(list(test_a.index), list(test_b.index))
        self.assertEqual(
            split["feature_group_overlap"],
            {"train_test": 0, "train_validation": 0, "validation_test": 0},
        )

    def test_filename_marks_the_dataset_synthetic(self):
        self.assertEqual(infer_provenance(OUTPUT_PATH), "synthetic")
        self.assertEqual(
            infer_provenance(SOURCE_PATH), "unknown"
        )

    def test_builder_mapping_covers_every_display_name(self):
        canonical = {
            breed for breeds in SUPPORTED_BREEDS.values() for breed in breeds
        }
        self.assertEqual(set(BREED_MAP.values()), canonical)
        self.assertEqual(len(BREED_MAP), 20)
        self.assertTrue(set(BREED_MAP).isdisjoint(canonical))
        self.assertEqual(
            {BREED_MAP[name] for name in BREED_MAP},
            canonical,
        )

    def test_header_is_exactly_six_columns(self):
        with OUTPUT_PATH.open(encoding="utf-8", newline="") as handle:
            header = next(csv.reader(handle))
        self.assertEqual(header, list(REQUIRED_COLUMNS))

    def test_age_band_metrics_cover_every_band(self):
        frame = pd.DataFrame(
            {
                "livestock_type": ["cattle"] * 4,
                "breed": ["brahman"] * 4,
                "sex": ["male"] * 4,
                "age_months": [2, 12, 24, 72],
                "weight_kg": [60.0, 150.0, 250.0, 320.0],
                "actual_sale_price": [12000.0, 30000.0, 50000.0, 62000.0],
            }
        )
        predictions = frame["actual_sale_price"].to_numpy(dtype=float)
        metrics = train_candidate._per_age_band_metrics(frame, predictions)
        self.assertEqual(
            list(metrics),
            ["under_6m", "6_to_18m", "18_to_60m", "60m_plus"],
        )
        for band in metrics.values():
            self.assertEqual(band["n"], 1)
            self.assertEqual(band["mae"], 0.0)

    def test_v5_candidate_lookup_never_falls_back_to_v4(self):
        with tempfile.TemporaryDirectory() as directory:
            models_dir = Path(directory)
            (
                models_dir
                / "candidate_catboost_v4_20260101T000000000000Z.cbm"
            ).write_bytes(b"")
            with mock.patch.object(evaluate_candidate, "MODELS_DIR", models_dir):
                with self.assertRaises(FileNotFoundError):
                    evaluate_candidate._latest_candidate("v5")


if __name__ == "__main__":
    unittest.main()
