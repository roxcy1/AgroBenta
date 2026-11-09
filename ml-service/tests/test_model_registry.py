import json
import tempfile
import unittest
from pathlib import Path

import pandas as pd
from catboost import CatBoostRegressor

from features import CATEGORICAL_FEATURES, FEATURE_COLUMNS, TARGET_COLUMN
from model_registry import (
    ModelConfigurationError,
    ModelIntegrityError,
    load_verified_model,
    sha256_file,
)
from validation import (
    build_safety_profile,
    build_training_profile,
    save_safety_profile,
    save_training_profile,
)


def training_frame() -> pd.DataFrame:
    rows = []
    for index in range(12):
        rows.append(
            {
                "livestock_type": "cattle",
                "breed": "brahman",
                "sex": "male" if index % 2 else "female",
                "age_months": 12 + index,
                "weight_kg": 200.0 + index * 10,
                TARGET_COLUMN: 50000.0 + index * 2000,
            }
        )
    return pd.DataFrame(rows)


def write_model_artifacts(
    directory: Path,
    filename: str,
) -> tuple[Path, dict]:
    frame = training_frame()
    model = CatBoostRegressor(
        iterations=5,
        depth=2,
        random_seed=1,
        verbose=False,
        allow_writing_files=False,
        thread_count=1,
    )
    model.fit(
        frame.loc[:, list(FEATURE_COLUMNS)],
        frame[TARGET_COLUMN],
        cat_features=list(CATEGORICAL_FEATURES),
        verbose=False,
    )
    path = directory / filename
    model.save_model(str(path))
    save_training_profile(
        path,
        build_training_profile(frame, model_file=path.name),
    )
    save_safety_profile(
        path,
        build_safety_profile(frame, model_file=path.name),
    )
    return path, {
        "model_version": "test",
        "model_file": path.name,
        "metadata_file": path.with_suffix(".metadata.json").name,
        "safety_profile_file": path.with_suffix(".safety.json").name,
        "sha256": sha256_file(path),
        "provenance": "synthetic",
        "status": "active",
    }


def write_manifest(directory: Path, active: dict, candidates=None) -> None:
    manifest = {
        "schema_version": 1,
        "active": active,
        "rollback": {"available": False},
        "candidates": candidates or [],
    }
    (directory / "active_model.json").write_text(
        json.dumps(manifest), encoding="utf-8"
    )


class ModelRegistryTests(unittest.TestCase):
    def test_loads_active_model_from_manifest(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            _, entry = write_model_artifacts(root, "catboost_price_v1_test.cbm")
            write_manifest(root, entry)

            model, path, loaded_entry, metadata, safety = load_verified_model(
                models_dir=root
            )

        self.assertEqual(path.name, entry["model_file"])
        self.assertEqual(loaded_entry["model_version"], "test")
        self.assertIn("cattle", metadata["observed_categories"])
        self.assertIn("cattle", safety["categories"])

    def test_model_path_selects_registered_candidate(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            _, active = write_model_artifacts(
                root, "catboost_price_v1_test.cbm"
            )
            candidate_path, candidate = write_model_artifacts(
                root, "candidate_model.cbm"
            )
            candidate["status"] = "candidate"
            write_manifest(root, active, [candidate])

            _, path, entry, _, _ = load_verified_model(
                models_dir=root,
                environ={"MODEL_PATH": str(candidate_path)},
            )

        self.assertEqual(path.name, "candidate_model.cbm")
        self.assertEqual(entry["model_version"], "test")

    def test_corrupt_model_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            path, entry = write_model_artifacts(
                root, "catboost_price_v1_test.cbm"
            )
            write_manifest(root, entry)
            path.write_bytes(path.read_bytes() + b"corrupt")

            with self.assertRaises(ModelIntegrityError):
                load_verified_model(models_dir=root)

    def test_missing_metadata_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            path, entry = write_model_artifacts(
                root, "catboost_price_v1_test.cbm"
            )
            path.with_suffix(".metadata.json").unlink()
            write_manifest(root, entry)

            with self.assertRaises(ModelIntegrityError):
                load_verified_model(models_dir=root)

    def test_missing_safety_profile_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            path, entry = write_model_artifacts(
                root, "catboost_price_v1_test.cbm"
            )
            path.with_suffix(".safety.json").unlink()
            write_manifest(root, entry)

            with self.assertRaises(ModelIntegrityError):
                load_verified_model(models_dir=root)

    def test_missing_manifest_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            write_model_artifacts(root, "catboost_price_v1_test.cbm")

            with self.assertRaises(ModelConfigurationError):
                load_verified_model(models_dir=root)

    def test_unregistered_test_model_requires_explicit_opt_in(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            path, _ = write_model_artifacts(
                root, "catboost_price_v1_test.cbm"
            )

            with self.assertRaises(ModelConfigurationError):
                load_verified_model(path, models_dir=root)

            model, loaded_path, entry, _, _ = load_verified_model(
                path,
                models_dir=root,
                allow_unregistered=True,
            )

        self.assertEqual(loaded_path, path)
        self.assertEqual(entry["model_version"], "unregistered")


if __name__ == "__main__":
    unittest.main()
