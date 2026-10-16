import tempfile
import unittest
from pathlib import Path
from unittest.mock import MagicMock, patch

from capture_orders import _append_order_row, _event_date, _load_seen_orders


class CaptureOrdersTests(unittest.TestCase):
    def test_event_date_parsing(self) -> None:
        self.assertEqual(_event_date("2026-10-10T12:00:00Z"), "2026-10-10")
        self.assertEqual(_event_date("2026-05-01T08:30:00+00:00"), "2026-05-01")

    def test_append_order_row_ignores_non_delivered(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            output_csv = Path(temp_dir) / "sales.csv"
            seen = set()
            event = {
                "orderNumber": "ORD-001",
                "orderStatus": "PLACED",
                "orderCreatedAt": "2026-10-10T10:00:00Z",
                "items": [{"sku": "SKU-001", "quantity": 2}],
            }
            written = _append_order_row(output_csv, event, seen)
            self.assertEqual(written, 0)
            self.assertFalse(output_csv.exists())

    def test_append_order_row_writes_delivered_items(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            output_csv = Path(temp_dir) / "sales.csv"
            seen = set()
            event = {
                "orderNumber": "ORD-002",
                "orderStatus": "DELIVERED",
                "orderCreatedAt": "2026-10-10T10:00:00Z",
                "items": [
                    {"sku": "SKU-001", "quantity": 3},
                    {"sku": "SKU-002", "quantity": 1},
                ],
            }
            written = _append_order_row(output_csv, event, seen)
            self.assertEqual(written, 2)
            self.assertTrue(output_csv.exists())
            self.assertIn("ORD-002", seen)

            # Deduplication: same order should not be appended twice
            duplicate_written = _append_order_row(output_csv, event, seen)
            self.assertEqual(duplicate_written, 0)

            # Reload seen orders
            reloaded_seen = _load_seen_orders(output_csv)
            self.assertEqual(reloaded_seen, {"ORD-002"})

    def test_kafka_python_config(self) -> None:
        from capture_orders import _kafka_python_config
        config = _kafka_python_config("test-broker:9092")
        self.assertEqual(config["bootstrap_servers"], "test-broker:9092")
        self.assertEqual(config["auto_offset_reset"], "earliest")
        self.assertEqual(config["security_protocol"], "PLAINTEXT")

    def test_append_order_row_skips_invalid_items(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            output_csv = Path(temp_dir) / "sales.csv"
            seen = set()
            event = {
                "orderNumber": "ORD-003",
                "orderStatus": "DELIVERED",
                "orderCreatedAt": "2026-10-10T10:00:00Z",
                "items": [
                    {"sku": "", "quantity": 3},
                    {"sku": "SKU-001", "quantity": 0},
                    {"sku": "SKU-002", "quantity": -5},
                ],
            }
            written = _append_order_row(output_csv, event, seen)
            self.assertEqual(written, 0)
            self.assertFalse(output_csv.exists())

    def test_run_python_capture_loop(self) -> None:
        import json
        from unittest.mock import MagicMock, patch
        from capture_orders import run_python_capture

        class DummyMessage:
            def __init__(self, value, partition=0, offset=0):
                self.value = value
                self.partition = partition
                self.offset = offset

        valid_event = {
            "orderNumber": "ORD-100",
            "orderStatus": "DELIVERED",
            "orderCreatedAt": "2026-10-10T10:00:00Z",
            "items": [{"sku": "SKU-001", "quantity": 2}],
        }
        messages = [
            DummyMessage(None),
            DummyMessage(b"not-valid-json"),
            DummyMessage(json.dumps(valid_event).encode("utf-8")),
        ]

        mock_consumer = MagicMock()
        mock_consumer.__iter__.return_value = messages

        with tempfile.TemporaryDirectory() as temp_dir:
            output_csv = Path(temp_dir) / "captured.csv"
            with patch("kafka.KafkaConsumer", return_value=mock_consumer):
                run_python_capture(
                    bootstrap_servers="mock:9092",
                    topic="orders-topic",
                    output=output_csv,
                    max_messages=3,
                )
                self.assertTrue(output_csv.exists())

    def test_main_cli_dispatch(self) -> None:
        from unittest.mock import patch
        from capture_orders import main, main_python, main_spark

        with patch("capture_orders.run_python_capture") as mock_python:
            main_python(["--bootstrap-servers", "test:9092", "--max-messages", "1"])
            self.assertTrue(mock_python.called)

        with patch("capture_orders.run_spark_capture") as mock_spark:
            main_spark(["--bootstrap-servers", "test:9092"])
            self.assertTrue(mock_spark.called)

        with patch("sys.argv", ["capture_orders.py", "--engine", "python"]):
            with patch("capture_orders.run_python_capture") as mock_python:
                main()
                self.assertTrue(mock_python.called)

        with patch("sys.argv", ["capture_orders.py", "--engine", "spark"]):
            with patch("capture_orders.run_spark_capture") as mock_spark:
                main()
                self.assertTrue(mock_spark.called)

    @patch("pyspark.sql.functions")
    def test_run_spark_capture_mock(self, mock_f) -> None:
        from unittest.mock import MagicMock, patch
        from capture_orders import run_spark_capture

        mock_spark = MagicMock()
        mock_builder = MagicMock()
        mock_builder.appName.return_value = mock_builder
        mock_builder.master.return_value = mock_builder
        mock_builder.config.return_value = mock_builder
        mock_builder.getOrCreate.return_value = mock_spark
        mock_query = MagicMock()
        mock_query.isActive = False

        mock_stream = MagicMock()
        mock_col = MagicMock()
        mock_col.__gt__.return_value = mock_col
        mock_col.__and__.return_value = mock_col
        mock_col.__rand__.return_value = mock_col
        mock_col.__eq__.return_value = mock_col
        mock_f.col.return_value = mock_col
        mock_f.upper.return_value = mock_col
        mock_f.coalesce.return_value = mock_col

        mock_spark.readStream.format.return_value = mock_stream
        mock_stream.option.return_value = mock_stream
        mock_stream.load.return_value = mock_stream
        mock_stream.select.return_value = mock_stream
        mock_stream.where.return_value = mock_stream
        mock_stream.withColumn.return_value = mock_stream
        mock_stream.writeStream.format.return_value = mock_stream
        mock_stream.outputMode.return_value = mock_stream
        mock_stream.partitionBy.return_value = mock_stream
        mock_stream.trigger.return_value = mock_stream
        mock_stream.start.return_value = mock_query

        with patch("pyspark.sql.SparkSession.builder", mock_builder):
            run_spark_capture()
            self.assertTrue(mock_spark.stop.called)


if __name__ == "__main__":
    unittest.main()
