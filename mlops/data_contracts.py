"""Data Contracts & Schema Validation for MLOps Pipeline."""

from __future__ import annotations

from datetime import date, datetime
from typing import Any

import pandas as pd


class DataContractViolation(ValueError):
    """Raised when an incoming event or dataset violates the MLOps data contract."""
    pass


def _validate_event_items(items: Any) -> None:
    if not isinstance(items, list) or len(items) == 0:
        raise DataContractViolation("Event 'items' must be a non-empty list")

    for idx, item in enumerate(items):
        if not isinstance(item, dict):
            raise DataContractViolation(f"Item at index {idx} must be a dictionary")
        sku = item.get("sku")
        if not sku or not isinstance(sku, str) or not sku.strip():
            raise DataContractViolation(f"Item at index {idx} has invalid 'sku'")
        quantity = item.get("quantity")
        if not isinstance(quantity, (int, float)) or quantity <= 0:
            raise DataContractViolation(f"Item at index {idx} must have positive quantity (got {quantity})")


def validate_order_event(event: dict[str, Any]) -> bool:
    """Validate incoming Kafka order events before ingestion into the sales dataset."""
    if not isinstance(event, dict):
        raise DataContractViolation("Event must be a dictionary")

    order_number = event.get("orderNumber")
    if not order_number or not isinstance(order_number, str) or not order_number.strip():
        raise DataContractViolation("Event missing required 'orderNumber' string")

    order_status = event.get("orderStatus")
    if not order_status or not isinstance(order_status, str):
        raise DataContractViolation("Event missing required 'orderStatus' string")

    created_at = event.get("orderCreatedAt")
    if not created_at or not isinstance(created_at, str):
        raise DataContractViolation("Event missing required 'orderCreatedAt' timestamp string")

    try:
        datetime.fromisoformat(created_at.replace("Z", "+00:00"))
    except ValueError as exc:
        raise DataContractViolation(f"Invalid 'orderCreatedAt' timestamp format: {created_at}") from exc

    _validate_event_items(event.get("items"))
    return True


def validate_sales_dataframe(df: pd.DataFrame) -> pd.DataFrame:
    """Validate that a sales DataFrame meets the schema contract for training/inference."""
    if not isinstance(df, pd.DataFrame):
        raise DataContractViolation("Expected a pandas DataFrame")

    required_columns = {"date", "product_id", "units_sold"}
    missing = required_columns.difference(df.columns)
    if missing:
        raise DataContractViolation(f"Sales DataFrame missing required columns: {', '.join(sorted(missing))}")

    if df.empty:
        raise DataContractViolation("Sales DataFrame is empty")

    # Check for negative units
    if (df["units_sold"] < 0).any():
        negative_count = int((df["units_sold"] < 0).sum())
        raise DataContractViolation(f"Sales DataFrame contains {negative_count} negative 'units_sold' records")

    return df
