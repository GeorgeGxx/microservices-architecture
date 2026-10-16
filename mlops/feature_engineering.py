"""Feature Engineering & Time-Series Transformations for Demand Forecasting."""

from __future__ import annotations

from datetime import date, timedelta
from typing import Sequence

import pandas as pd


def build_daily_spine(df: pd.DataFrame) -> pd.DataFrame:
    """Ensure a continuous daily time-series per product, filling missing dates with 0.0 units."""
    if df.empty:
        return df.copy()

    clean_df = df.copy()
    if not pd.api.types.is_datetime64_any_dtype(clean_df["date"]):
        clean_df["date"] = pd.to_datetime(clean_df["date"]).dt.date

    result_frames = []
    for product_id, group in clean_df.groupby("product_id"):
        min_date = group["date"].min()
        max_date = group["date"].max()

        # Build full date range
        date_range = [min_date + timedelta(days=i) for i in range((max_date - min_date).days + 1)]
        spine = pd.DataFrame({"date": date_range, "product_id": product_id})

        merged = pd.merge(
            spine,
            group[["date", "product_id", "units_sold"]],
            on=["date", "product_id"],
            how="left",
            validate="1:1",
        )
        merged["units_sold"] = merged["units_sold"].fillna(0.0).astype(float)
        result_frames.append(merged)

    return pd.concat(result_frames, ignore_index=True)


def compute_lag_features(df: pd.DataFrame, lags: Sequence[int] = (1, 7)) -> pd.DataFrame:
    """Compute lag features grouped by product without future information leakage."""
    if df.empty:
        return df.copy()

    result = df.copy().sort_values(by=["product_id", "date"])
    for lag in lags:
        result[f"lag_{lag}"] = result.groupby("product_id")["units_sold"].shift(lag)

    return result


def add_calendar_features(df: pd.DataFrame) -> pd.DataFrame:
    """Add calendar attributes such as day of week, day of year, and weekend indicator."""
    if df.empty:
        return df.copy()

    result = df.copy()
    dates = pd.to_datetime(result["date"])
    result["day_of_week"] = dates.dt.dayofweek
    result["day_of_year"] = dates.dt.dayofyear
    result["is_weekend"] = result["day_of_week"].isin([5, 6])
    return result


def chronological_train_test_split(
    df: pd.DataFrame, test_days: int = 7
) -> tuple[pd.DataFrame, pd.DataFrame]:
    """Split time-series data chronologically so that train strictly precedes test."""
    if df.empty:
        return df.copy(), df.copy()

    unique_dates = sorted(df["date"].unique())
    if len(unique_dates) <= test_days:
        split_point = max(1, len(unique_dates) // 2)
        test_start = unique_dates[split_point]
    else:
        test_start = unique_dates[-test_days]

    train = df[df["date"] < test_start].copy()
    test = df[df["date"] >= test_start].copy()
    return train, test
