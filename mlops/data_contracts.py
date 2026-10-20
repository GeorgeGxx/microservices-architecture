"""Data Contracts, Quality & Freshness Validation for MLOps Pipeline."""

from __future__ import annotations

import argparse
import sys
from datetime import date, datetime, timedelta
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

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


def validate_data_quality_and_freshness(
    df: pd.DataFrame,
    max_staleness_days: int = 7,
    min_history_days: int = 8,
    reference_date: Optional[date] = None,
) -> Dict[str, Any]:
    """
    Comprehensive data quality and freshness gate for MLOps training & inference.
    Checks:
      1. Schema & non-empty validation
      2. Missing / null values in key columns
      3. Value range & extreme outlier detection
      4. Data freshness against reference date
      5. Minimum historical depth per SKU
    """
    validate_sales_dataframe(df)

    violations: List[str] = []
    warnings: List[str] = []

    # 1. Null checks
    null_counts = df[["date", "product_id", "units_sold"]].isnull().sum().to_dict()
    for col, count in null_counts.items():
        if count > 0:
            violations.append(f"Column '{col}' has {count} null/NaN values")

    # Clean working copy for metrics
    clean = df.dropna(subset=["date", "product_id", "units_sold"]).copy()
    clean["date"] = pd.to_datetime(clean["date"]).dt.date
    clean["units_sold"] = pd.to_numeric(clean["units_sold"], errors="coerce")

    # 2. Outlier bounds (> 50,000 units sold in a single transaction/day)
    outliers = int((clean["units_sold"] > 50000).sum())
    if outliers > 0:
        violations.append(f"Dataset contains {outliers} outlier records exceeding 50,000 units")

    # 3. Duplicate checks
    if "order_number" in clean.columns:
        dupes = int(clean.duplicated(subset=["order_number", "product_id"]).sum())
        if dupes > 0:
            warnings.append(f"Dataset contains {dupes} duplicate (order_number, product_id) rows")

    # 4. Freshness check
    min_date = clean["date"].min()
    max_date = clean["date"].max()
    ref_d = reference_date or date.today()
    staleness_days = (ref_d - max_date).days

    if staleness_days > max_staleness_days:
        violations.append(
            f"Data freshness violation: latest record date is {max_date} ({staleness_days} days old, max allowed: {max_staleness_days} days)"
        )

    # 5. SKU depth
    sku_counts: Dict[str, int] = {}
    for sku, group in clean.groupby("product_id"):
        sku_depth = (group["date"].max() - group["date"].min()).days + 1
        sku_counts[str(sku)] = sku_depth
        if sku_depth < min_history_days:
            warnings.append(f"SKU '{sku}' has only {sku_depth} days of history (min required for lag-7: {min_history_days})")

    quality_passed = len(violations) == 0

    return {
        "passed": quality_passed,
        "rows_count": len(clean),
        "unique_skus": len(sku_counts),
        "min_date": str(min_date),
        "max_date": str(max_date),
        "staleness_days": staleness_days,
        "sku_depths": sku_counts,
        "violations": violations,
        "warnings": warnings,
    }


def main() -> None:
    parser = argparse.ArgumentParser(description="Validate MLOps sales dataset quality and freshness.")
    parser.add_argument("--input-csv", help="Path to input sales CSV file")
    parser.add_argument("--input-parquet", help="Path to input sales Parquet directory")
    parser.add_argument("--max-staleness-days", type=int, default=7, help="Maximum allowed days of staleness")
    parser.add_argument("--min-history-days", type=int, default=8, help="Minimum days of history per SKU")
    args = parser.parse_args()

    df = None
    if args.input_csv:
        p = Path(args.input_csv)
        if not p.exists():
            print(f"[ERROR] File not found: {p}", file=sys.stderr)
            sys.exit(1)
        df = pd.read_csv(p)
    elif args.input_parquet:
        p = Path(args.input_parquet)
        if not p.exists():
            print(f"[ERROR] Parquet path not found: {p}", file=sys.stderr)
            sys.exit(1)
        df = pd.read_parquet(p)
    else:
        print("[ERROR] Please provide --input-csv or --input-parquet", file=sys.stderr)
        sys.exit(1)

    try:
        report = validate_data_quality_and_freshness(
            df,
            max_staleness_days=args.max_staleness_days,
            min_history_days=args.min_history_days,
        )
        print("MLOps Dataset Quality & Freshness Audit:")
        print(f"  * Status:         {'PASS' if report['passed'] else 'FAIL'}")
        print(f"  * Rows Count:     {report['rows_count']}")
        print(f"  * Unique SKUs:    {report['unique_skus']}")
        print(f"  * Date Range:     {report['min_date']} to {report['max_date']}")
        print(f"  * Staleness:      {report['staleness_days']} days (threshold: {args.max_staleness_days}d)")
        if report["warnings"]:
            print("  * Warnings:")
            for w in report["warnings"]:
                print(f"    - {w}")
        if report["violations"]:
            print("  * Violations:")
            for v in report["violations"]:
                print(f"    - {v}")
            sys.exit(2)
        sys.exit(0)
    except Exception as exc:
        print(f"[ERROR] Validation failed: {exc}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
