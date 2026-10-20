"""TDD Data Contract & Schema Validation Tests for MLOps Pipeline."""

from __future__ import annotations

import tempfile
import unittest
from datetime import date
from pathlib import Path
from unittest.mock import MagicMock, patch

try:
    from pyspark import SparkContext
    if SparkContext._active_spark_context is None:
        SparkContext._active_spark_context = MagicMock()
except ImportError:
    pass

import pandas as pd

from data_contracts import (
    DataContractViolation,
    _validate_event_items,
    main,
    validate_data_quality_and_freshness,
    validate_order_event,
    validate_sales_dataframe,
    validate_spark_sales_dataframe,
)


class DataContractsTests(unittest.TestCase):
    def test_valid_order_event_passes(self) -> None:
        event = {
            "orderNumber": "ORD-100",
            "orderStatus": "DELIVERED",
            "orderCreatedAt": "2026-10-10T14:30:00Z",
            "items": [
                {"sku": "SKU-PROD-001", "quantity": 2},
                {"sku": "SKU-PROD-002", "quantity": 1},
            ],
        }
        self.assertTrue(validate_order_event(event))

    def test_invalid_event_type_raises_violation(self) -> None:
        with self.assertRaises(DataContractViolation) as ctx:
            validate_order_event("not-a-dict")  # type: ignore
        self.assertIn("must be a dictionary", str(ctx.exception))

    def test_missing_order_number_raises_violation(self) -> None:
        event = {
            "orderStatus": "DELIVERED",
            "orderCreatedAt": "2026-10-10T14:30:00Z",
            "items": [{"sku": "SKU-001", "quantity": 1}],
        }
        with self.assertRaises(DataContractViolation) as ctx:
            validate_order_event(event)
        self.assertIn("orderNumber", str(ctx.exception))

        event_blank = {
            "orderNumber": "   ",
            "orderStatus": "DELIVERED",
            "orderCreatedAt": "2026-10-10T14:30:00Z",
            "items": [{"sku": "SKU-001", "quantity": 1}],
        }
        with self.assertRaises(DataContractViolation) as ctx:
            validate_order_event(event_blank)
        self.assertIn("orderNumber", str(ctx.exception))

    def test_missing_order_status_raises_violation(self) -> None:
        event = {
            "orderNumber": "ORD-101",
            "orderCreatedAt": "2026-10-10T14:30:00Z",
            "items": [{"sku": "SKU-001", "quantity": 1}],
        }
        with self.assertRaises(DataContractViolation) as ctx:
            validate_order_event(event)
        self.assertIn("orderStatus", str(ctx.exception))

    def test_invalid_order_status_type_raises_violation(self) -> None:
        event = {
            "orderNumber": "ORD-101",
            "orderStatus": 12345,  # must be str
            "orderCreatedAt": "2026-10-10T14:30:00Z",
            "items": [{"sku": "SKU-001", "quantity": 1}],
        }
        with self.assertRaises(DataContractViolation):
            validate_order_event(event)

    def test_missing_created_at_raises_violation(self) -> None:
        event = {
            "orderNumber": "ORD-101",
            "orderStatus": "DELIVERED",
            "items": [{"sku": "SKU-001", "quantity": 1}],
        }
        with self.assertRaises(DataContractViolation) as ctx:
            validate_order_event(event)
        self.assertIn("orderCreatedAt", str(ctx.exception))

    def test_invalid_date_format_raises_violation(self) -> None:
        event = {
            "orderNumber": "ORD-102",
            "orderStatus": "DELIVERED",
            "orderCreatedAt": "not-a-date",
            "items": [{"sku": "SKU-001", "quantity": 1}],
        }
        with self.assertRaises(DataContractViolation):
            validate_order_event(event)

    def test_empty_or_negative_quantity_raises_violation(self) -> None:
        event_empty = {
            "orderNumber": "ORD-103",
            "orderStatus": "DELIVERED",
            "orderCreatedAt": "2026-10-10T14:30:00Z",
            "items": [],
        }
        with self.assertRaises(DataContractViolation):
            validate_order_event(event_empty)

        event_negative = {
            "orderNumber": "ORD-104",
            "orderStatus": "DELIVERED",
            "orderCreatedAt": "2026-10-10T14:30:00Z",
            "items": [{"sku": "SKU-001", "quantity": -5}],
        }
        with self.assertRaises(DataContractViolation):
            validate_order_event(event_negative)

    def test_validate_event_items_variations(self) -> None:
        with self.assertRaises(DataContractViolation):
            _validate_event_items("not-a-list")

        with self.assertRaises(DataContractViolation):
            _validate_event_items(["not-a-dict"])

        with self.assertRaises(DataContractViolation):
            _validate_event_items([{"sku": "", "quantity": 1}])

        with self.assertRaises(DataContractViolation):
            _validate_event_items([{"sku": "SKU-1", "quantity": "zero"}])

    def test_valid_sales_dataframe_passes(self) -> None:
        df = pd.DataFrame([
            {"date": date(2026, 10, 1), "product_id": "SKU-A", "units_sold": 10.0},
            {"date": date(2026, 10, 2), "product_id": "SKU-A", "units_sold": 15.0},
        ])
        clean_df = validate_sales_dataframe(df)
        self.assertEqual(len(clean_df), 2)

    def test_not_a_dataframe_raises_violation(self) -> None:
        with self.assertRaises(DataContractViolation) as ctx:
            validate_sales_dataframe("not-a-df")  # type: ignore
        self.assertIn("Expected a pandas DataFrame", str(ctx.exception))

    def test_empty_sales_dataframe_raises_violation(self) -> None:
        df = pd.DataFrame(columns=["date", "product_id", "units_sold"])
        with self.assertRaises(DataContractViolation) as ctx:
            validate_sales_dataframe(df)
        self.assertIn("empty", str(ctx.exception))

    def test_missing_sales_dataframe_columns_raises_violation(self) -> None:
        df = pd.DataFrame([
            {"date": date(2026, 10, 1), "product_id": "SKU-A"}
        ])
        with self.assertRaises(DataContractViolation) as ctx:
            validate_sales_dataframe(df)
        self.assertIn("units_sold", str(ctx.exception))

    def test_negative_units_sold_raises_violation(self) -> None:
        df = pd.DataFrame([
            {"date": date(2026, 10, 1), "product_id": "SKU-A", "units_sold": -2.0}
        ])
        with self.assertRaises(DataContractViolation):
            validate_sales_dataframe(df)

    def test_non_numeric_units_sold_raises_violation(self) -> None:
        df = pd.DataFrame([
            {"date": date(2026, 10, 1), "product_id": "SKU-A", "units_sold": "invalid"}
        ])
        with self.assertRaises(DataContractViolation) as ctx:
            validate_sales_dataframe(df)
        self.assertIn("non-numeric", str(ctx.exception))

    def test_invalid_date_in_sales_dataframe_raises_violation(self) -> None:
        df = pd.DataFrame([
            {"date": "invalid-date", "product_id": "SKU-A", "units_sold": 5.0}
        ])
        with self.assertRaises(DataContractViolation) as ctx:
            validate_sales_dataframe(df)
        self.assertIn("invalid 'date'", str(ctx.exception))

    def test_blank_product_id_in_sales_dataframe_raises_violation(self) -> None:
        df = pd.DataFrame([
            {"date": date(2026, 10, 1), "product_id": "   ", "units_sold": 5.0}
        ])
        with self.assertRaises(DataContractViolation) as ctx:
            validate_sales_dataframe(df)
        self.assertIn("blank 'product_id'", str(ctx.exception))

    def test_validate_data_quality_and_freshness_success(self) -> None:
        today = date(2026, 10, 20)
        rows = [
            {"date": date(2026, 10, 11) + pd.Timedelta(days=i), "product_id": "SKU-A", "units_sold": 5 + i}
            for i in range(10)
        ]
        df = pd.DataFrame(rows)
        report = validate_data_quality_and_freshness(df, max_staleness_days=7, min_history_days=8, reference_date=today)
        self.assertTrue(report["passed"])
        self.assertEqual(len(report["violations"]), 0)
        self.assertEqual(report["staleness_days"], 0)

    def test_validate_data_quality_null_counts(self) -> None:
        today = date(2026, 10, 20)
        df = pd.DataFrame([
            {"date": None, "product_id": "SKU-A", "units_sold": 5},
            {"date": today, "product_id": "SKU-A", "units_sold": 10},
        ])
        with self.assertRaises(DataContractViolation):
            validate_data_quality_and_freshness(df, reference_date=today)

    def test_validate_data_quality_duplicate_warning(self) -> None:
        today = date(2026, 10, 20)
        rows = [
            {"date": date(2026, 10, 11) + pd.Timedelta(days=i), "product_id": "SKU-A", "units_sold": 5, "order_number": f"ORD-{i}"}
            for i in range(10)
        ]
        # duplicate one order row
        rows.append({"date": date(2026, 10, 11), "product_id": "SKU-A", "units_sold": 5, "order_number": "ORD-0"})
        df = pd.DataFrame(rows)
        report = validate_data_quality_and_freshness(df, reference_date=today)
        self.assertTrue(report["passed"])
        self.assertTrue(any("duplicate" in w for w in report["warnings"]))

    def test_validate_data_quality_freshness_violation(self) -> None:
        today = date(2026, 10, 20)
        rows = [
            {"date": date(2026, 9, 1), "product_id": "SKU-A", "units_sold": 10.0}
        ]
        df = pd.DataFrame(rows)
        report = validate_data_quality_and_freshness(df, max_staleness_days=7, reference_date=today)
        self.assertFalse(report["passed"])
        self.assertTrue(any("freshness violation" in v for v in report["violations"]))

    def test_validate_data_quality_outlier_violation(self) -> None:
        today = date(2026, 10, 20)
        rows = [
            {"date": today, "product_id": "SKU-A", "units_sold": 999999.0}
        ]
        df = pd.DataFrame(rows)
        report = validate_data_quality_and_freshness(df, max_staleness_days=7, reference_date=today)
        self.assertFalse(report["passed"])
        self.assertTrue(any("outlier" in v for v in report["violations"]))

    def test_validate_data_quality_short_history_fails_gate(self) -> None:
        today = date(2026, 10, 20)
        df = pd.DataFrame([
            {"date": date(2026, 10, 19), "product_id": "SKU-A", "units_sold": 3},
            {"date": today, "product_id": "SKU-A", "units_sold": 4},
        ])
        report = validate_data_quality_and_freshness(df, reference_date=today)
        self.assertFalse(report["passed"])
        self.assertTrue(any("minimum required" in item for item in report["violations"]))

    # -------------------------------------------------------------------------
    # Spark DataFrame Validation Tests
    # -------------------------------------------------------------------------
    def test_validate_spark_sales_dataframe_success(self) -> None:
        today = date(2026, 10, 20)
        frame = MagicMock()
        frame.columns = ["date", "product_id", "units_sold"]
        frame.agg.return_value.first.return_value.asDict.return_value = {
            "rows_count": 50,
            "null_dates": 0,
            "invalid_products": 0,
            "invalid_units": 0,
            "negative_units": 0,
            "outliers": 0,
            "min_date": date(2026, 10, 1),
            "max_date": today,
        }
        frame.groupBy.return_value.agg.return_value.where.return_value.select.return_value.limit.return_value.collect.return_value = []
        result = validate_spark_sales_dataframe(frame, reference_date=today)
        self.assertTrue(result["passed"])
        self.assertEqual(result["rows_count"], 50)
        self.assertEqual(len(result["violations"]), 0)

    def test_validate_spark_sales_dataframe_missing_columns(self) -> None:
        frame = MagicMock()
        frame.columns = ["date", "product_id"]  # missing units_sold
        with self.assertRaises(DataContractViolation) as ctx:
            validate_spark_sales_dataframe(frame)
        self.assertIn("units_sold", str(ctx.exception))

    def test_validate_spark_sales_dataframe_empty(self) -> None:
        frame = MagicMock()
        frame.columns = ["date", "product_id", "units_sold"]
        frame.agg.return_value.first.return_value.asDict.return_value = {
            "rows_count": 0,
            "null_dates": 0,
            "invalid_products": 0,
            "invalid_units": 0,
            "negative_units": 0,
            "outliers": 0,
            "min_date": None,
            "max_date": None,
        }
        frame.groupBy.return_value.agg.return_value.where.return_value.select.return_value.limit.return_value.collect.return_value = []
        result = validate_spark_sales_dataframe(frame)
        self.assertFalse(result["passed"])
        self.assertTrue(any("empty" in v for v in result["violations"]))

    def test_validate_spark_sales_dataframe_violations_detected(self) -> None:
        today = date(2026, 10, 20)
        frame = MagicMock()
        frame.columns = ["date", "product_id", "units_sold"]
        frame.agg.return_value.first.return_value.asDict.return_value = {
            "rows_count": 100,
            "null_dates": 2,
            "invalid_products": 3,
            "invalid_units": 4,
            "negative_units": 5,
            "outliers": 6,
            "min_date": date(2026, 1, 1),
            "max_date": date(2026, 9, 1),  # stale
        }
        frame.groupBy.return_value.agg.return_value.where.return_value.select.return_value.limit.return_value.collect.return_value = [
            {"product_id": "SKU-SHORT", "history_days": 3}
        ]
        result = validate_spark_sales_dataframe(frame, max_staleness_days=7, reference_date=today)
        self.assertFalse(result["passed"])
        self.assertTrue(any("missing/invalid dates" in v for v in result["violations"]))
        self.assertTrue(any("missing/blank product IDs" in v for v in result["violations"]))
        self.assertTrue(any("non-numeric" in v for v in result["violations"]))
        self.assertTrue(any("negative" in v for v in result["violations"]))
        self.assertTrue(any("outliers" in v or "above" in v for v in result["violations"]))
        self.assertTrue(any("freshness" in v for v in result["violations"]))
        self.assertTrue(any("less than 8 calendar days" in v for v in result["violations"]))

    def test_validate_spark_sales_dataframe_future_dates(self) -> None:
        today = date(2026, 10, 20)
        frame = MagicMock()
        frame.columns = ["date", "product_id", "units_sold"]
        frame.agg.return_value.first.return_value.asDict.return_value = {
            "rows_count": 10,
            "null_dates": 0,
            "invalid_products": 0,
            "invalid_units": 0,
            "negative_units": 0,
            "outliers": 0,
            "min_date": today,
            "max_date": date(2026, 11, 1),  # future
        }
        frame.groupBy.return_value.agg.return_value.where.return_value.select.return_value.limit.return_value.collect.return_value = []
        result = validate_spark_sales_dataframe(frame, reference_date=today)
        self.assertFalse(result["passed"])
        self.assertTrue(any("future dates" in v for v in result["violations"]))

    # -------------------------------------------------------------------------
    # CLI main() Tests
    # -------------------------------------------------------------------------
    def test_main_cli_csv_success(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            csv_path = Path(td) / "sales.csv"
            rows = [
                {"date": date(2026, 10, 11) + pd.Timedelta(days=i), "product_id": "SKU-A", "units_sold": 5 + i}
                for i in range(10)
            ]
            pd.DataFrame(rows).to_csv(csv_path, index=False)
            with patch("sys.argv", ["data_contracts.py", "--input-csv", str(csv_path), "--max-staleness-days", "30"]):
                with self.assertRaises(SystemExit) as cm:
                    main()
                self.assertEqual(cm.exception.code, 0)

    def test_main_cli_parquet_success(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            parquet_path = Path(td) / "sales.parquet"
            rows = [
                {"date": date(2026, 10, 11) + pd.Timedelta(days=i), "product_id": "SKU-A", "units_sold": 5 + i}
                for i in range(10)
            ]
            pd.DataFrame(rows).to_parquet(parquet_path, index=False)
            with patch("sys.argv", ["data_contracts.py", "--input-parquet", str(parquet_path), "--max-staleness-days", "30"]):
                with self.assertRaises(SystemExit) as cm:
                    main()
                self.assertEqual(cm.exception.code, 0)

    def test_main_cli_missing_file_exits_1(self) -> None:
        with patch("sys.argv", ["data_contracts.py", "--input-csv", "non_existent.csv"]):
            with self.assertRaises(SystemExit) as cm:
                main()
            self.assertEqual(cm.exception.code, 1)

        with patch("sys.argv", ["data_contracts.py", "--input-parquet", "non_existent.parquet"]):
            with self.assertRaises(SystemExit) as cm:
                main()
            self.assertEqual(cm.exception.code, 1)

    def test_main_cli_no_args_exits_1(self) -> None:
        with patch("sys.argv", ["data_contracts.py"]):
            with self.assertRaises(SystemExit) as cm:
                main()
            self.assertEqual(cm.exception.code, 1)

    def test_main_cli_violations_exits_2(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            csv_path = Path(td) / "sales.csv"
            # 1 row from last year -> staleness violation
            pd.DataFrame([{"date": date(2025, 1, 1), "product_id": "SKU-A", "units_sold": 5}]).to_csv(csv_path, index=False)
            with patch("sys.argv", ["data_contracts.py", "--input-csv", str(csv_path), "--max-staleness-days", "7"]):
                with self.assertRaises(SystemExit) as cm:
                    main()
                self.assertEqual(cm.exception.code, 2)

    def test_main_cli_with_warnings(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            csv_path = Path(td) / "sales.csv"
            # create duplicates with order_number
            today = date.today()
            rows = [
                {"date": today - pd.Timedelta(days=i), "product_id": "SKU-A", "units_sold": 5, "order_number": "ORD-1"}
                for i in range(10)
            ]
            rows.append({"date": today, "product_id": "SKU-A", "units_sold": 2, "order_number": "ORD-1"})
            pd.DataFrame(rows).to_csv(csv_path, index=False)
            with patch("sys.argv", ["data_contracts.py", "--input-csv", str(csv_path), "--max-staleness-days", "30"]):
                with self.assertRaises(SystemExit) as cm:
                    main()
                self.assertEqual(cm.exception.code, 0)

    def test_main_cli_unexpected_exception_exits_1(self) -> None:
        with patch("data_contracts.validate_data_quality_and_freshness", side_effect=RuntimeError("disk error")):
            with tempfile.TemporaryDirectory() as td:
                csv_path = Path(td) / "sales.csv"
                pd.DataFrame([{"date": "2026-10-10", "product_id": "A", "units_sold": 1}]).to_csv(csv_path, index=False)
                with patch("sys.argv", ["data_contracts.py", "--input-csv", str(csv_path)]):
                    with self.assertRaises(SystemExit) as cm:
                        main()
                    self.assertEqual(cm.exception.code, 1)


if __name__ == "__main__":
    unittest.main()
