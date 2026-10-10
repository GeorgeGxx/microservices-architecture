import tempfile
import unittest
from datetime import date
from pathlib import Path

from train_demand_model import evaluate_champion_candidate, snapshot_dataset


class TrainDemandModelTests(unittest.TestCase):
    def test_snapshot_empty_directory(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            dates, fingerprint = snapshot_dataset(Path(temp_dir))
            self.assertEqual(dates, [])
            self.assertEqual(fingerprint, "")

    def test_snapshot_valid_partitions(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            base = Path(temp_dir)
            p1 = base / "date=2026-10-01"
            p1.mkdir()
            (p1 / "part-0.parquet").write_bytes(b"dummy-parquet-data-1")

            p2 = base / "date=2026-10-02"
            p2.mkdir()
            (p2 / "part-0.parquet").write_bytes(b"dummy-parquet-data-2")

            dates, fingerprint = snapshot_dataset(base)
            self.assertEqual(dates, [date(2026, 10, 1), date(2026, 10, 2)])
            self.assertTrue(len(fingerprint) == 64)  # Valid SHA-256 hex string

    def test_evaluate_champion_initial_baseline(self) -> None:
        is_champion, status = evaluate_champion_candidate(candidate_rmse=3.5, prior_rmse=None)
        self.assertTrue(is_champion)
        self.assertEqual(status, "PROMOTED_INITIAL_BASELINE")

    def test_evaluate_champion_improved(self) -> None:
        is_champion, status = evaluate_champion_candidate(candidate_rmse=2.9, prior_rmse=3.5)
        self.assertTrue(is_champion)
        self.assertEqual(status, "PROMOTED_IMPROVED_OR_COMPARABLE")

    def test_evaluate_champion_within_tolerance(self) -> None:
        # 3.55 is within 2% of 3.50 (3.5 * 1.02 = 3.57)
        is_champion, status = evaluate_champion_candidate(candidate_rmse=3.55, prior_rmse=3.50)
        self.assertTrue(is_champion)
        self.assertEqual(status, "PROMOTED_IMPROVED_OR_COMPARABLE")

    def test_evaluate_champion_rejected_degraded(self) -> None:
        # 4.2 is significantly worse than 3.5
        is_champion, status = evaluate_champion_candidate(candidate_rmse=4.2, prior_rmse=3.5)
        self.assertFalse(is_champion)
        self.assertEqual(status, "REJECTED_DEGRADED")


if __name__ == "__main__":
    unittest.main()
