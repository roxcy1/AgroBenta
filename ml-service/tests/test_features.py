import unittest

from features import (
    DatasetValidationError,
    InputValidationError,
    normalize_label,
    parse_peso_price,
    validate_and_normalize_frame,
    validate_feature_values,
)
import pandas as pd


class PesoParsingTests(unittest.TestCase):
    def test_parses_peso_formatted_values(self):
        self.assertEqual(parse_peso_price("\u20b115,570"), 15570.0)
        self.assertEqual(parse_peso_price("PHP 15,570.50"), 15570.5)
        self.assertEqual(parse_peso_price("15,570"), 15570.0)
        self.assertEqual(parse_peso_price("15570.25"), 15570.25)
        self.assertEqual(parse_peso_price(15570), 15570.0)

    def test_rejects_non_positive_or_unparseable_values(self):
        for value in ("", "abc", "\u20b10", "-5", 0, float("nan")):
            with self.subTest(value=value):
                with self.assertRaises(InputValidationError):
                    parse_peso_price(value)


class LabelValidationTests(unittest.TestCase):
    def test_normalizes_labels(self):
        self.assertEqual(normalize_label("  CATTLE "), "cattle")

    def test_accepts_supported_combination(self):
        values = validate_feature_values(
            "CATTLE", "Brahman", "Male", 48, 350.5
        )
        self.assertEqual(values["livestock_type"], "cattle")
        self.assertEqual(values["breed"], "brahman")
        self.assertEqual(values["sex"], "male")
        self.assertEqual(values["age_months"], 48.0)
        self.assertEqual(values["weight_kg"], 350.5)

    def test_rejects_unsupported_category_and_breed_pair(self):
        with self.assertRaises(InputValidationError):
            validate_feature_values("cattle", "boer", "male", 48, 350)
        with self.assertRaises(InputValidationError):
            validate_feature_values("chicken", "brahman", "male", 3, 2)

    def test_rejects_invalid_sex(self):
        with self.assertRaises(InputValidationError):
            validate_feature_values("cattle", "brahman", "unknown", 48, 350)

    def test_rejects_invalid_age_and_weight(self):
        with self.assertRaises(InputValidationError):
            validate_feature_values("cattle", "brahman", "male", 0, 350)
        with self.assertRaises(InputValidationError):
            validate_feature_values("cattle", "brahman", "male", 301, 350)
        with self.assertRaises(InputValidationError):
            validate_feature_values("cattle", "brahman", "male", 48, 0)
        with self.assertRaises(InputValidationError):
            validate_feature_values("cattle", "brahman", "male", 48, -1)

    def test_frame_validation_normalizes_and_ignores_extra_columns(self):
        frame = pd.DataFrame(
            [
                {
                    "livestock_type": "CATTLE",
                    "breed": "Brahman",
                    "sex": "Male",
                    "age_months": 48,
                    "weight_kg": 350.5,
                    "actual_sale_price": "\u20b1124,090",
                    "source": "test",
                }
            ]
        )
        normalized, ignored = validate_and_normalize_frame(frame)
        self.assertEqual(ignored, ["source"])
        self.assertEqual(normalized.iloc[0]["livestock_type"], "cattle")
        self.assertEqual(normalized.iloc[0]["breed"], "brahman")
        self.assertEqual(normalized.iloc[0]["sex"], "male")
        self.assertEqual(normalized.iloc[0]["actual_sale_price"], 124090.0)

    def test_frame_validation_rejects_missing_column(self):
        frame = pd.DataFrame(
            [{"livestock_type": "cattle", "breed": "brahman"}]
        )
        with self.assertRaises(DatasetValidationError):
            validate_and_normalize_frame(frame)


if __name__ == "__main__":
    unittest.main()
