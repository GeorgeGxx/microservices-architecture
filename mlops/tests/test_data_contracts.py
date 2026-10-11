"""TDD Data Contract & Schema Validation Tests for MLOps Pipeline."""

from __future__ import annotations

import unittest
from datetime import date

import pandas as pd

from data_contracts import (
    DataContractViolation,
    validate_order_event,
    validate_sales_dataframe,
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

    def test_missing_order_number_raises_violation(self) -> None:
        event = {
            "orderStatus": "DELIVERED",
            "orderCreatedAt": "2026-10-10T14:30:00Z",
            "items": [{"sku": "SKU-001", "quantity": 1}],
        }
        with self.assertRaises(DataContractViolation) as ctx:
            validate_order_event(event)
        self.assertIn("orderNumber", str(ctx.exception))

    def test_invalid_order_status_type_raises_violation(self) -> None:
        event = {
            "orderNumber": "ORD-101",
            "orderStatus": 12345,  # must be str
            "orderCreatedAt": "2026-10-10T14:30:00Z",
            "items": [{"sku": "SKU-001", "quantity": 1}],
        }
        with self.assertRaises(DataContractViolation):
            validate_order_event(event)

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

    def test_valid_sales_dataframe_passes(self) -> None:
        df = pd.DataFrame([
            {"date": date(2026, 10, 1), "product_id": "SKU-A", "units_sold": 10.0},
            {"date": date(2026, 10, 2), "product_id": "SKU-A", "units_sold": 15.0},
        ])
        clean_df = validate_sales_dataframe(df)
        self.assertEqual(len(clean_df), 2)

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


if __name__ == "__main__":
    unittest.main()
