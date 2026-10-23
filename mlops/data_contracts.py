"""Data Contracts, Quality & Freshness Validation for MLOps Pipeline."""

from __future__ import annotations

import argparse
import sys
from datetime import date, datetime
from pathlib import Path
from typing import Any, Dict, List, Optional

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

    units = pd.to_numeric(df["units_sold"], errors="coerce")
    invalid_units = df["units_sold"].notna() & units.isna()
    if invalid_units.any():
        raise DataContractViolation(
            f"Sales DataFrame contains {int(invalid_units.sum())} non-numeric 'units_sold' records"
        )
    if (units < 0).any():
        negative_count = int((units < 0).sum())
        raise DataContractViolation(f"Sales DataFrame contains {negative_count} negative 'units_sold' records")

    if df["date"].isna().any() or pd.to_datetime(df["date"], errors="coerce").isna().any():
        raise DataContractViolation("Sales DataFrame contains missing or invalid 'date' records")
    product_ids = df["product_id"].astype("string").str.strip()
    if product_ids.isna().any() or product_ids.eq("").any():
        raise DataContractViolation("Sales DataFrame contains missing or blank 'product_id' records")

    return df


def _collect_spark_row_violations(row: Dict[str, Any], max_units_per_row: float) -> List[str]:
    violations: List[str] = []
    if not row["rows_count"]:
        violations.append("Sales DataFrame is empty")
    for key, description in (
        ("null_dates", "missing/invalid dates"),
        ("invalid_products", "missing/blank product IDs"),
        ("invalid_units", "missing/non-numeric unit quantities"),
        ("negative_units", "negative unit quantities"),
        ("outliers", f"unit quantities above {max_units_per_row:g}"),
    ):
        count = int(row.get(key) or 0)
        if count:
            violations.append(f"Dataset contains {count} records with {description}")
    return violations


def _collect_spark_date_violations(
    max_date: Any, today: date, max_staleness_days: int
) -> tuple[Optional[int], List[str]]:
    if not max_date:
        return None, []
    staleness_days = (today - max_date).days
    violations: List[str] = []
    if staleness_days > max_staleness_days:
        violations.append(
            f"Data freshness violation: latest record date is {max_date} "
            f"({staleness_days} days old, max allowed: {max_staleness_days} days)"
        )
    elif staleness_days < 0:
        violations.append(f"Sales data contains future dates through {max_date}")
    return staleness_days, violations


def validate_spark_sales_dataframe(
    frame: Any,
    max_staleness_days: int = 7,
    min_history_days: int = 8,
    max_units_per_row: float = 50000,
    reference_date: Optional[date] = None,
) -> Dict[str, Any]:
    """Apply the sales quality gate using Spark aggregations without collecting the dataset."""
    from pyspark.sql import functions as F

    required = {"date", "product_id", "units_sold"}
    missing = required.difference(frame.columns)
    if missing:
        raise DataContractViolation(f"Sales DataFrame missing required columns: {', '.join(sorted(missing))}")

    row = frame.agg(
        F.count(F.lit(1)).alias("rows_count"),
        F.sum(F.when(F.col("date").isNull(), 1).otherwise(0)).alias("null_dates"),
        F.sum(
            F.when(F.col("product_id").isNull() | (F.trim(F.col("product_id")) == ""), 1).otherwise(0)
        ).alias("invalid_products"),
        F.sum(F.when(F.col("units_sold").isNull() | F.isnan("units_sold"), 1).otherwise(0)).alias("invalid_units"),
        F.sum(F.when(F.col("units_sold") < 0, 1).otherwise(0)).alias("negative_units"),
        F.sum(F.when(F.col("units_sold") > max_units_per_row, 1).otherwise(0)).alias("outliers"),
        F.min("date").alias("min_date"),
        F.max("date").alias("max_date"),
    ).first().asDict()

    violations = _collect_spark_row_violations(row, max_units_per_row)
    min_date = row["min_date"]
    max_date = row["max_date"]
    today = reference_date or date.today()
    staleness_days, date_violations = _collect_spark_date_violations(max_date, today, max_staleness_days)
    violations.extend(date_violations)

    shallow = (
        frame.groupBy("product_id")
        .agg((F.datediff(F.max("date"), F.min("date")) + F.lit(1)).alias("history_days"))
        .where(F.col("history_days") < min_history_days)
        .select("product_id", "history_days")
        .limit(5)
        .collect()
    )
    if shallow:
        samples = ", ".join(f"{item['product_id']} ({item['history_days']}d)" for item in shallow)
        violations.append(
            f"Products with less than {min_history_days} calendar days of history: {samples}"
        )

    return {
        "passed": not violations,
        "rows_count": int(row["rows_count"] or 0),
        "min_date": str(min_date) if min_date else None,
        "max_date": str(max_date) if max_date else None,
        "staleness_days": staleness_days,
        "violations": violations,
    }


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
            violations.append(
                f"SKU '{sku}' has only {sku_depth} calendar days of history "
                f"(minimum required: {min_history_days})"
            )

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
