import tempfile
import unittest
from datetime import date
from pathlib import Path
from unittest.mock import MagicMock, patch

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
            self.assertEqual(len(fingerprint), 64)  # Valid SHA-256 hex string

    def test_snapshot_skips_hidden_and_invalid(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            base = Path(temp_dir)
            p1 = base / "date=2026-10-01"
            p1.mkdir()
            (p1 / "part.parquet").write_bytes(b"good")

            (base / "other_dir").mkdir()
            (base / "date=not-a-date").mkdir()
            (base / "date=2026-10-02").write_text("not a dir")
            hidden_dir = base / "_temporary"
            hidden_dir.mkdir()
            (hidden_dir / "temp.parquet").write_bytes(b"temp")
            (p1 / "._hidden.parquet").write_bytes(b"hidden")
            (p1 / "readme.txt").write_text("hello")

            dates, fingerprint = snapshot_dataset(base)
            self.assertEqual(dates, [date(2026, 10, 1)])
            self.assertEqual(len(fingerprint), 64)

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

    def test_snapshot_non_existent_directory(self) -> None:
        dates, fingerprint = snapshot_dataset(Path("non_existent_dir_12345"))
        self.assertEqual(dates, [])
        self.assertEqual(fingerprint, "")

    def test_resolve_input_format(self) -> None:
        from train_demand_model import _resolve_input_format
        self.assertEqual(_resolve_input_format("sales.csv", None), "csv")
        self.assertEqual(_resolve_input_format(None, "sales_parquet"), "parquet")
        self.assertEqual(_resolve_input_format(None, None), "generated_sample")

    def test_check_auto_training_readiness_not_auto(self) -> None:
        from train_demand_model import _check_auto_training_readiness
        proceed, state_path, fingerprint, parquet_path = _check_auto_training_readiness(False, "sample_path")
        self.assertTrue(proceed)
        self.assertIsNone(state_path)
        self.assertIsNone(fingerprint)
        self.assertEqual(parquet_path, "sample_path")

    def test_check_auto_training_readiness_empty_dataset(self) -> None:
        from train_demand_model import _check_auto_training_readiness
        with tempfile.TemporaryDirectory() as temp_dir:
            proceed, _, _, _ = _check_auto_training_readiness(True, temp_dir)
            self.assertFalse(proceed)

    def test_query_prior_champion_rmse(self) -> None:
        from unittest.mock import MagicMock
        from train_demand_model import _query_prior_champion_rmse

        mock_client = MagicMock()
        mock_exp = MagicMock()
        mock_exp.experiment_id = "exp-1"
        mock_client.get_experiment_by_name.return_value = mock_exp

        mock_run = MagicMock()
        mock_run.data.metrics = {"rmse": 2.75}
        mock_client.search_runs.return_value = [mock_run]

        rmse = _query_prior_champion_rmse(mock_client, "inventory-demand-forecast")
        self.assertEqual(rmse, 2.75)

    def test_check_auto_training_readiness_insufficient_partitions(self) -> None:
        from train_demand_model import _check_auto_training_readiness
        with tempfile.TemporaryDirectory() as temp_dir:
            base = Path(temp_dir)
            p1 = base / "date=2026-10-01"
            p1.mkdir()
            (p1 / "part.parquet").write_bytes(b"data")
            proceed, _, _, _ = _check_auto_training_readiness(True, str(base))
            self.assertFalse(proceed)

    def test_check_auto_training_readiness_unmodified_state(self) -> None:
        import os
        from unittest.mock import patch
        from train_demand_model import _check_auto_training_readiness
        with tempfile.TemporaryDirectory() as temp_dir:
            base = Path(temp_dir)
            for i in range(1, 11):
                p = base / f"date=2026-10-{i:02d}"
                p.mkdir()
                (p / "part.parquet").write_bytes(f"data-{i}".encode("ascii"))
            dates, fp = snapshot_dataset(base)
            state_file = base / "state.sha256"
            state_file.write_text(fp)
            with patch.dict(os.environ, {"MLOPS_TRAINING_STATE_PATH": str(state_file)}):
                proceed, _, _, _ = _check_auto_training_readiness(True, str(base))
                self.assertFalse(proceed)

    def test_main_auto_skips_when_empty(self) -> None:
        from unittest.mock import patch
        from train_demand_model import main
        with tempfile.TemporaryDirectory() as temp_dir:
            with patch("sys.argv", ["train_demand_model.py", "--auto", "--input-parquet", temp_dir]):
                exit_code = main()
                self.assertEqual(exit_code, 0)

    def test_sample_sales(self) -> None:
        from unittest.mock import MagicMock
        from train_demand_model import sample_sales
        mock_spark = MagicMock()
        mock_spark.createDataFrame.return_value = "dummy-df"
        df = sample_sales(mock_spark, days=5)
        self.assertEqual(df, "dummy-df")
        self.assertTrue(mock_spark.createDataFrame.called)

    @patch("pyspark.sql.functions")
    def test_read_sales_csv_and_parquet(self, mock_f) -> None:
        from unittest.mock import MagicMock
        from train_demand_model import read_sales

        mock_spark = MagicMock()
        mock_df = MagicMock()
        mock_df.columns = ["date", "product_id", "units_sold", "order_number"]
        mock_df.dropDuplicates.return_value = mock_df
        mock_df.select.return_value = mock_df
        mock_spark.read.option.return_value.option.return_value.csv.return_value = mock_df
        mock_spark.read.parquet.return_value = mock_df

        # Test CSV path
        csv_df = read_sales(mock_spark, "sales.csv", None)
        self.assertEqual(csv_df, mock_df)

        # Test Parquet path
        pq_df = read_sales(mock_spark, None, "sales_parquet")
        self.assertEqual(pq_df, mock_df)

    def test_read_sales_missing_columns_raises(self) -> None:
        from unittest.mock import MagicMock
        from train_demand_model import read_sales

        mock_spark = MagicMock()
        mock_df = MagicMock()
        mock_df.columns = ["date", "product_id"]  # Missing units_sold
        mock_spark.read.option.return_value.option.return_value.csv.return_value = mock_df

        with self.assertRaises(ValueError):
            read_sales(mock_spark, "sales.csv", None)

    def test_check_auto_training_readiness_proceeds(self) -> None:
        import os
        from unittest.mock import patch
        from train_demand_model import _check_auto_training_readiness
        with tempfile.TemporaryDirectory() as temp_dir:
            base = Path(temp_dir)
            for i in range(1, 11):
                p = base / f"date=2026-10-{i:02d}"
                p.mkdir()
                (p / "part.parquet").write_bytes(f"data-{i}".encode("ascii"))
            state_file = base / "non_existent_state.sha256"
            with patch.dict(os.environ, {"MLOPS_TRAINING_STATE_PATH": str(state_file)}):
                proceed, sp, fp, resolved = _check_auto_training_readiness(True, str(base))
                self.assertTrue(proceed)
                self.assertIsNotNone(sp)
                self.assertIsNotNone(fp)
                self.assertEqual(resolved, str(base.resolve()))

    def test_query_prior_champion_rmse_empty_or_none(self) -> None:
        from train_demand_model import _query_prior_champion_rmse
        mock_client = MagicMock()
        mock_client.get_experiment_by_name.return_value = None
        self.assertIsNone(_query_prior_champion_rmse(mock_client, "none"))

        mock_exp = MagicMock()
        mock_client.get_experiment_by_name.return_value = mock_exp
        mock_client.search_runs.return_value = []
        self.assertIsNone(_query_prior_champion_rmse(mock_client, "empty"))

    def test_read_sales_sample_fallback(self) -> None:
        from train_demand_model import read_sales
        mock_spark = MagicMock()
        mock_spark.createDataFrame.return_value = "sample-sales-df"
        res = read_sales(mock_spark, None, None)
        self.assertEqual(res, "sample-sales-df")

    @patch("pyspark.sql.functions")
    def test_read_sales_parquet_with_partitions(self, mock_f) -> None:
        from train_demand_model import read_sales
        with tempfile.TemporaryDirectory() as temp_dir:
            base = Path(temp_dir)
            (base / "date=2026-10-01").mkdir()
            mock_spark = MagicMock()
            mock_df = MagicMock()
            mock_df.columns = ["date", "product_id", "units_sold"]
            mock_df.select.return_value = mock_df
            mock_spark.read.option.return_value.parquet.return_value = mock_df
            res = read_sales(mock_spark, None, str(base))
            self.assertEqual(res, mock_df)


if __name__ == "__main__":
    unittest.main()
