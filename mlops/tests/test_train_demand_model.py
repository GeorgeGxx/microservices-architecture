import tempfile
import sys
import types
import unittest
from datetime import date
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import MagicMock, patch

import pandas as pd

from train_demand_model import evaluate_champion_candidate, snapshot_dataset


class TrainDemandModelTests(unittest.TestCase):
    class _ColumnExpression:
        def desc(self):
            return self

        def __lt__(self, other):
            return "before-test-window"

        def __ge__(self, other):
            return "test-window-or-later"

    def _main_dependencies(self, *, empty_sales: bool = False, empty_train: bool = False):
        """Build a small Spark/MLflow double to exercise the training orchestration."""
        sales = MagicMock()
        sales.columns = ["date", "product_id", "units_sold"]
        sales.withColumn.return_value = sales
        sales.isEmpty.return_value = empty_sales

        daily_sales = MagicMock()
        sales.groupBy.return_value.agg.return_value = daily_sales
        product_ranges = MagicMock()
        daily_sales.groupBy.return_value.agg.return_value = product_ranges
        date_spine = MagicMock()
        product_ranges.select.return_value = date_spine
        joined = MagicMock()
        date_spine.join.return_value = joined
        daily = MagicMock()
        joined.select.return_value = daily
        features = MagicMock()
        daily.withColumn.return_value = daily
        daily.na.drop.return_value = features

        date_selection = MagicMock()
        distinct_dates = MagicMock()
        features.select.return_value = date_selection
        date_selection.distinct.return_value = distinct_dates
        distinct_dates.count.return_value = 20
        ordered_dates = MagicMock()
        distinct_dates.orderBy.return_value = ordered_dates
        limited_dates = MagicMock()
        ordered_dates.limit.return_value = limited_dates
        aggregate_dates = MagicMock()
        limited_dates.agg.return_value = aggregate_dates
        aggregate_dates.first.return_value = (date(2026, 10, 1),)

        train = MagicMock()
        test = MagicMock()
        features.where.side_effect = [train, test]
        train.isEmpty.return_value = empty_train
        test.isEmpty.return_value = False
        train.select.return_value.toPandas.return_value = pd.DataFrame(
            {"lag_1": [2.0, 3.0], "lag_7": [1.0, 2.0], "day_of_week": [1, 2], "day_of_year": [1, 2], "units_sold": [4.0, 5.0]}
        )
        test.select.return_value.toPandas.return_value = pd.DataFrame(
            {"lag_1": [3.0, 4.0], "lag_7": [2.0, 3.0], "day_of_week": [3, 4], "day_of_year": [3, 4], "units_sold": [5.0, 6.0]}
        )

        spark = MagicMock()
        builder = MagicMock()
        builder.appName.return_value = builder
        builder.master.return_value = builder
        builder.config.return_value = builder
        builder.getOrCreate.return_value = spark
        spark_session = SimpleNamespace(builder=builder)
        functions = MagicMock()
        functions.col.side_effect = lambda *_: self._ColumnExpression()
        functions.lit.side_effect = lambda *_: self._ColumnExpression()
        sql_module = SimpleNamespace(
            SparkSession=spark_session,
            Window=SimpleNamespace(partitionBy=MagicMock(return_value=SimpleNamespace(orderBy=MagicMock(return_value="window")))),
            functions=functions,
        )

        model = MagicMock()
        model.predict.return_value = [5.0, 5.0]
        sklearn_module = types.ModuleType("sklearn")
        sklearn_module.__path__ = []
        ensemble_module = types.ModuleType("sklearn.ensemble")
        ensemble_module.RandomForestRegressor = MagicMock(return_value=model)
        sklearn_module.ensemble = ensemble_module
        run = SimpleNamespace(info=SimpleNamespace(run_id="test-run"))
        mlflow = MagicMock()
        mlflow.start_run.return_value.__enter__.return_value = run
        mlflow.tracking = SimpleNamespace(MlflowClient=MagicMock())
        mlflow.sklearn = SimpleNamespace(log_model=MagicMock())
        return sales, spark, model, sql_module, mlflow, sklearn_module, ensemble_module

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
        from train_demand_model import _resolve_dataset_fingerprint, _resolve_input_format
        self.assertEqual(_resolve_input_format("sales.csv", None), "csv")
        self.assertEqual(_resolve_input_format(None, "sales_parquet"), "parquet")
        self.assertEqual(_resolve_input_format(None, None), "generated_sample")
        self.assertEqual(_resolve_dataset_fingerprint(None, None, "precomputed"), "precomputed")
        self.assertEqual(_resolve_dataset_fingerprint(None, None, None), "generated_sample")
        self.assertEqual(_resolve_dataset_fingerprint("missing.csv", None, None), "csv")
        with tempfile.TemporaryDirectory() as temp_dir:
            csv_file = Path(temp_dir) / "sales.csv"
            csv_file.write_text("date,product_id,units_sold\n2026-10-01,SKU-1,5\n")
            self.assertEqual(len(_resolve_dataset_fingerprint(str(csv_file), None, None)), 64)
            self.assertEqual(_resolve_dataset_fingerprint(None, temp_dir, None), "parquet")

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

        rmse = _query_prior_champion_rmse(mock_client, "inventory-demand-forecast", "parquet", "fp-123")
        self.assertEqual(rmse, 2.75)
        self.assertIn(
            "params.input_format = 'parquet'",
            mock_client.search_runs.call_args.kwargs["filter_string"],
        )
        self.assertIn(
            "params.dataset_fingerprint = 'fp-123'",
            mock_client.search_runs.call_args.kwargs["filter_string"],
        )

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

    def test_query_prior_champion_rmse_handles_tracking_failure(self) -> None:
        from train_demand_model import _query_prior_champion_rmse

        client = MagicMock()
        client.get_experiment_by_name.side_effect = RuntimeError("offline")
        with patch("builtins.print"):
            self.assertIsNone(_query_prior_champion_rmse(client, "exp"))

    def test_main_completes_training_and_records_auto_state(self) -> None:
        from train_demand_model import main

        sales, spark, model, sql_module, mlflow, sklearn_module, ensemble_module = self._main_dependencies()
        with tempfile.TemporaryDirectory() as temp_dir:
            state_path = Path(temp_dir) / "last-successful.sha256"
            parquet_path = Path(temp_dir) / "sales"
            with (
                patch.dict(sys.modules, {"pyspark.sql": sql_module, "mlflow": mlflow, "sklearn": sklearn_module, "sklearn.ensemble": ensemble_module}),
                patch("data_contracts.validate_spark_sales_dataframe", return_value={"passed": True, "rows_count": 100, "min_date": "2026-01-01", "max_date": "2026-10-20", "staleness_days": 0, "violations": []}),
                patch("train_demand_model.read_sales", return_value=sales),
                patch("train_demand_model._check_auto_training_readiness", return_value=(True, state_path, "fingerprint-123", str(parquet_path))),
                patch("train_demand_model._query_prior_champion_rmse", return_value=None),
                patch("sys.argv", ["train_demand_model.py", "--auto", "--input-parquet", str(parquet_path)]),
                patch("builtins.print"),
            ):
                self.assertEqual(main(), 0)
            self.assertTrue(state_path.exists())
            self.assertEqual(state_path.read_text(encoding="ascii"), "fingerprint-123\n")
            self.assertTrue(mlflow.sklearn.log_model.called)
            spark.stop.assert_called_once()

    def test_main_rejects_data_missing_required_columns(self) -> None:
        from train_demand_model import main

        sales, spark, _, sql_module, mlflow, sklearn_module, ensemble_module = self._main_dependencies()
        sales.columns = ["date", "product_id"]
        with (
            patch.dict(sys.modules, {"pyspark.sql": sql_module, "mlflow": mlflow, "sklearn": sklearn_module, "sklearn.ensemble": ensemble_module}),
            patch("data_contracts.validate_spark_sales_dataframe", return_value={"passed": True, "rows_count": 100, "min_date": "2026-01-01", "max_date": "2026-10-20", "staleness_days": 0, "violations": []}),
            patch("train_demand_model.read_sales", return_value=sales),
            patch("sys.argv", ["train_demand_model.py"]),
        ):
            with self.assertRaisesRegex(ValueError, "missing required columns: units_sold"):
                main()
        spark.stop.assert_called_once()

    def test_main_rejects_empty_sales(self) -> None:
        from train_demand_model import main

        sales, spark, _, sql_module, mlflow, sklearn_module, ensemble_module = self._main_dependencies(empty_sales=True)
        with (
            patch.dict(sys.modules, {"pyspark.sql": sql_module, "mlflow": mlflow, "sklearn": sklearn_module, "sklearn.ensemble": ensemble_module}),
            patch("train_demand_model.read_sales", return_value=sales),
            patch("sys.argv", ["train_demand_model.py"]),
        ):
            with self.assertRaisesRegex(ValueError, "No usable sales rows"):
                main()
        spark.stop.assert_called_once()

    def test_main_rejects_empty_train_split(self) -> None:
        from train_demand_model import main

        sales, spark, _, sql_module, mlflow, sklearn_module, ensemble_module = self._main_dependencies(empty_train=True)
        with (
            patch.dict(sys.modules, {"pyspark.sql": sql_module, "mlflow": mlflow, "sklearn": sklearn_module, "sklearn.ensemble": ensemble_module}),
            patch("data_contracts.validate_spark_sales_dataframe", return_value={"passed": True, "rows_count": 100, "min_date": "2026-01-01", "max_date": "2026-10-20", "staleness_days": 0, "violations": []}),
            patch("train_demand_model.read_sales", return_value=sales),
            patch("sys.argv", ["train_demand_model.py"]),
        ):
            with self.assertRaisesRegex(ValueError, "Need enough dated sales rows"):
                main()
        spark.stop.assert_called_once()

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

    def test_check_auto_training_readiness_stability_window_lifecycle(self) -> None:
        import os
        import time
        from train_demand_model import _check_auto_training_readiness, CANDIDATE_STATE_FILENAME

        with tempfile.TemporaryDirectory() as temp_dir:
            base = Path(temp_dir)
            for i in range(1, 11):
                p = base / f"date=2026-10-{i:02d}"
                p.mkdir()
                (p / "part.parquet").write_bytes(f"data-{i}".encode("ascii"))
            state_file = base / "state.sha256"
            candidate_file = base / CANDIDATE_STATE_FILENAME

            with patch.dict(
                os.environ,
                {"MLOPS_TRAINING_STATE_PATH": str(state_file), "MLOPS_AUTO_TRAIN_STABILITY_SECONDS": "60"},
            ):
                # 1. Corrupt candidate file is handled gracefully and overwritten with new candidate state
                candidate_file.write_text("corrupt-single-line", encoding="ascii")
                proceed, _, _, _ = _check_auto_training_readiness(True, str(base))
                self.assertFalse(proceed)
                self.assertTrue(candidate_file.is_file())

                # 2. Second call within stability window waits and returns False
                proceed, _, _, _ = _check_auto_training_readiness(True, str(base))
                self.assertFalse(proceed)

                # 3. Once stability window has elapsed, auto-training proceeds
                _, fp = snapshot_dataset(base)
                candidate_file.write_text(f"{fp}\n{time.time() - 120.0:.6f}\n", encoding="ascii")
                proceed, sp, returned_fp, resolved = _check_auto_training_readiness(True, str(base))
                self.assertTrue(proceed)
                self.assertEqual(sp, state_file.resolve())
                self.assertEqual(returned_fp, fp)
                self.assertEqual(resolved, str(base.resolve()))

    def test_main_fails_when_sales_quality_gate_fails(self) -> None:
        from train_demand_model import main

        sales, spark, _, sql_module, mlflow, sklearn_module, ensemble_module = self._main_dependencies()
        with (
            patch.dict(sys.modules, {"pyspark.sql": sql_module, "mlflow": mlflow, "sklearn": sklearn_module, "sklearn.ensemble": ensemble_module}),
            patch(
                "data_contracts.validate_spark_sales_dataframe",
                return_value={
                    "passed": False,
                    "rows_count": 10,
                    "min_date": "2026-01-01",
                    "max_date": "2026-01-05",
                    "staleness_days": 90,
                    "violations": ["Data freshness violation"],
                },
            ),
            patch("train_demand_model.read_sales", return_value=sales),
            patch("sys.argv", ["train_demand_model.py"]),
            patch("builtins.print"),
        ):
            with self.assertRaisesRegex(ValueError, "Sales quality gate failed: Data freshness violation"):
                main()
        spark.stop.assert_called_once()

    def test_main_logs_challenger_rejected_and_improved_champion(self) -> None:
        from train_demand_model import main

        # 1. Challenger rejected when prior champion RMSE is much lower
        sales, spark, _, sql_module, mlflow, sklearn_module, ensemble_module = self._main_dependencies()
        with (
            patch.dict(sys.modules, {"pyspark.sql": sql_module, "mlflow": mlflow, "sklearn": sklearn_module, "sklearn.ensemble": ensemble_module}),
            patch("data_contracts.validate_spark_sales_dataframe", return_value={"passed": True, "rows_count": 100, "min_date": "2026-01-01", "max_date": "2026-10-20", "staleness_days": 0, "violations": []}),
            patch("train_demand_model.read_sales", return_value=sales),
            patch("train_demand_model._query_prior_champion_rmse", return_value=0.05),
            patch("sys.argv", ["train_demand_model.py"]),
            patch("builtins.print"),
        ):
            self.assertEqual(main(), 0)
        mlflow.set_tag.assert_any_call("model_role", "challenger_rejected")

        # 2. Champion promoted when improved over prior champion RMSE
        sales2, spark2, _, sql_module2, mlflow2, sklearn_module2, ensemble_module2 = self._main_dependencies()
        with (
            patch.dict(sys.modules, {"pyspark.sql": sql_module2, "mlflow": mlflow2, "sklearn": sklearn_module2, "sklearn.ensemble": ensemble_module2}),
            patch("data_contracts.validate_spark_sales_dataframe", return_value={"passed": True, "rows_count": 100, "min_date": "2026-01-01", "max_date": "2026-10-20", "staleness_days": 0, "violations": []}),
            patch("train_demand_model.read_sales", return_value=sales2),
            patch("train_demand_model._query_prior_champion_rmse", return_value=10.0),
            patch("sys.argv", ["train_demand_model.py"]),
            patch("builtins.print"),
        ):
            self.assertEqual(main(), 0)
        mlflow2.set_tag.assert_any_call("model_role", "champion")
        mlflow2.log_metric.assert_any_call("prior_champion_rmse", 10.0)


if __name__ == "__main__":
    unittest.main()
