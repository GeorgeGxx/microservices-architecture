import tempfile
import unittest
from pathlib import Path

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


if __name__ == "__main__":
    unittest.main()
