"""TDD Feature Engineering & Invariant Transformation Tests for MLOps."""

from __future__ import annotations

import unittest
from datetime import date, timedelta

import pandas as pd

from feature_engineering import (
    add_calendar_features,
    build_daily_spine,
    chronological_train_test_split,
    compute_lag_features,
)


class FeatureEngineeringTests(unittest.TestCase):
    def test_build_daily_spine_fills_date_gaps_with_zeros(self) -> None:
        # Product has sales on Oct 1 and Oct 3, but missing Oct 2
        df = pd.DataFrame([
            {"date": date(2026, 10, 1), "product_id": "SKU-01", "units_sold": 5.0},
            {"date": date(2026, 10, 3), "product_id": "SKU-01", "units_sold": 10.0},
        ])
        spined = build_daily_spine(df)
        self.assertEqual(len(spined), 3)

        oct_2_row = spined[spined["date"] == date(2026, 10, 2)]
        self.assertEqual(len(oct_2_row), 1)
        self.assertEqual(float(oct_2_row.iloc[0]["units_sold"]), 0.0)

    def test_compute_lag_features_without_leakage(self) -> None:
        start = date(2026, 9, 1)
        rows = [
            {"date": start + timedelta(days=i), "product_id": "SKU-01", "units_sold": float(i + 1)}
            for i in range(10)
        ]
        df = pd.DataFrame(rows)
        spined = build_daily_spine(df)
        lagged = compute_lag_features(spined, lags=[1, 7])

        # lag_1 for day 5 (units_sold = 6) should be units_sold of day 4 (5.0)
        day_5 = lagged[lagged["date"] == start + timedelta(days=5)].iloc[0]
        self.assertEqual(float(day_5["lag_1"]), 5.0)

        # lag_7 for day 8 (units_sold = 9) should be units_sold of day 1 (2.0)
        day_8 = lagged[lagged["date"] == start + timedelta(days=8)].iloc[0]
        self.assertEqual(float(day_8["lag_7"]), 2.0)

    def test_add_calendar_features_correctness(self) -> None:
        # 2026-10-11 is a Sunday (weekday=6 in python, 7 in iso)
        df = pd.DataFrame([
            {"date": date(2026, 10, 11), "product_id": "SKU-01", "units_sold": 8.0}
        ])
        enriched = add_calendar_features(df)
        row = enriched.iloc[0]
        self.assertIn("day_of_week", enriched.columns)
        self.assertIn("day_of_year", enriched.columns)
        self.assertIn("is_weekend", enriched.columns)
        self.assertTrue(bool(row["is_weekend"]))

    def test_chronological_train_test_split_guarantees_no_temporal_leakage(self) -> None:
        start = date(2026, 8, 1)
        rows = [
            {"date": start + timedelta(days=i), "product_id": "SKU-01", "units_sold": float(i)}
            for i in range(30)
        ]
        df = pd.DataFrame(rows)
        train, test = chronological_train_test_split(df, test_days=7)

        self.assertEqual(len(test), 7)
        self.assertEqual(len(train), 23)
        self.assertLess(train["date"].max(), test["date"].min())


if __name__ == "__main__":
    unittest.main()
