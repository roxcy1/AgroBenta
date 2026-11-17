import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import register_model
from model_registry import load_verified_model
from tests.test_model_registry import write_manifest, write_model_artifacts


class ModelRegistrationTests(unittest.TestCase):
    def test_candidate_registration_preserves_active_and_activation_records_rollback(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            active_path, active_entry = write_model_artifacts(root, "active.cbm")
            candidate_path, candidate_entry = write_model_artifacts(
                root, "candidate.cbm"
            )
            candidate_entry["status"] = "candidate"
            manifest_path = root / "active_model.json"
            write_manifest(root, active_entry)

            with patch.object(register_model, "MANIFEST_PATH", manifest_path):
                registered = register_model.register_candidate(
                    candidate_path,
                    version="v4",
                    provenance="synthetic",
                )

                manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
                self.assertEqual(manifest["active"]["model_file"], active_path.name)
                self.assertEqual(
                    [entry["model_file"] for entry in manifest["candidates"]],
                    [candidate_path.name],
                )
                self.assertEqual(registered["training_rows"], 12)

                activated = register_model.activate(
                    candidate_path,
                    version="v4",
                    provenance="synthetic",
                )

                manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
                self.assertEqual(activated["model_file"], candidate_path.name)
                self.assertEqual(
                    manifest["active"]["model_file"], candidate_path.name
                )
                self.assertTrue(manifest["rollback"]["available"])
                self.assertEqual(
                    manifest["rollback"]["target_model_file"],
                    active_path.name,
                )
                self.assertEqual(manifest["candidates"], [])

    def test_registers_revised_safety_profile_and_loads_it(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            _active_path, active_entry = write_model_artifacts(root, "active.cbm")
            path, _candidate_entry = write_model_artifacts(
                root, "candidate.cbm"
            )
            original = json.loads(
                path.with_suffix(".safety.json").read_text(encoding="utf-8")
            )
            original["schema_version"] = 2
            original["revised_marker"] = "safety-v2"
            revised_path = path.with_suffix(".safety_v2.json")
            revised_path.write_text(json.dumps(original), encoding="utf-8")

            manifest_path = root / "active_model.json"
            write_manifest(root, active_entry)

            with patch.object(register_model, "MANIFEST_PATH", manifest_path):
                registered = register_model.register_candidate(
                    path,
                    version="v5",
                    provenance="synthetic",
                    safety_profile=revised_path,
                )

            self.assertEqual(registered["safety_profile_file"], revised_path.name)
            self.assertEqual(registered["safety_schema_version"], 2)

            model, loaded_path, loaded_entry, _metadata, safety = (
                load_verified_model(path, models_dir=root)
            )
            self.assertEqual(loaded_path.name, path.name)
            self.assertEqual(
                loaded_entry["safety_profile_file"], revised_path.name
            )
            self.assertEqual(safety["schema_version"], 2)
            self.assertEqual(safety["revised_marker"], "safety-v2")

    def test_rejects_a_safety_profile_outside_the_model_directory(self):
        with tempfile.TemporaryDirectory() as directory, (
            tempfile.TemporaryDirectory()
        ) as other_directory:
            root = Path(directory)
            path, entry = write_model_artifacts(root, "candidate.cbm")
            manifest_path = root / "active_model.json"
            write_manifest(root, entry)
            stray = Path(other_directory) / "candidate.safety_v2.json"
            stray.write_text(
                path.with_suffix(".safety.json").read_text(encoding="utf-8"),
                encoding="utf-8",
            )
            with patch.object(register_model, "MANIFEST_PATH", manifest_path):
                with self.assertRaises(register_model.ModelConfigurationError):
                    register_model.register_candidate(
                        path,
                        version="v5",
                        provenance="synthetic",
                        safety_profile=stray,
                    )

    def test_unregistered_or_incomplete_candidate_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            path, _ = write_model_artifacts(root, "candidate.cbm")
            path.with_suffix(".safety.json").unlink()
            manifest_path = root / "active_model.json"
            write_manifest(
                root,
                {
                    "model_version": "v1",
                    "model_file": "active.cbm",
                    "metadata_file": "active.metadata.json",
                    "safety_profile_file": "active.safety.json",
                    "sha256": "a" * 64,
                    "provenance": "synthetic",
                    "status": "active",
                    "training_rows": 1,
                },
            )

            with patch.object(register_model, "MANIFEST_PATH", manifest_path):
                with self.assertRaises(register_model.ModelConfigurationError):
                    register_model.register_candidate(
                        path,
                        version="v4",
                        provenance="synthetic",
                    )


if __name__ == "__main__":
    unittest.main()
