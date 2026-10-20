"""TDD Model Invariants, Monotonicity & Safety Gate Tests for MLOps."""

from __future__ import annotations

import unittest
from datetime import date, timedelta
from unittest.mock import MagicMock

import numpy as np
import pandas as pd
from sklearn.ensemble import RandomForestRegressor

from model_invariants import (
    clamp_predictions,
    evaluate_champion_safety_gate,
    generate_bounded_forecast,
    validate_model_predictions,
)


class ModelInvariantsTests(unittest.TestCase):
    def test_clamp_predictions_removes_negative_and_nan(self) -> None:
        raw_preds = np.array([-5.2, 0.0, 14.8, np.nan, -0.01])
        clamped = clamp_predictions(raw_preds, min_value=0.0)
        self.assertTrue(np.all(clamped >= 0.0))
        self.assertFalse(np.any(np.isnan(clamped)))
        self.assertEqual(clamped[0], 0.0)
        self.assertEqual(clamped[2], 14.8)

    def test_validate_model_predictions_passes_valid_array(self) -> None:
        valid_preds = np.array([10.0, 12.5, 14.0, 11.2, 9.8, 15.0, 13.1])
        is_valid, msg = validate_model_predictions(valid_preds, expected_len=7)
        self.assertTrue(is_valid)
        self.assertEqual(msg, "OK")

    def test_validate_model_predictions_rejects_wrong_length_or_nan(self) -> None:
        short_preds = np.array([10.0, 12.0])
        is_valid, _ = validate_model_predictions(short_preds, expected_len=7)
        self.assertFalse(is_valid)

        nan_preds = np.array([10.0, np.nan, 14.0, 11.2, 9.8, 15.0, 13.1])
        is_valid, msg = validate_model_predictions(nan_preds, expected_len=7)
        self.assertFalse(is_valid)
        self.assertIn("NaN", msg)

        inf_preds = np.array([10.0, np.inf, 14.0, 11.2, 9.8, 15.0, 13.1])
        is_valid_inf, msg_inf = validate_model_predictions(inf_preds, expected_len=7)
        self.assertFalse(is_valid_inf)
        self.assertIn("infinite", msg_inf)

        neg_preds = np.array([10.0, -2.0, 14.0, 11.2, 9.8, 15.0, 13.1])
        is_valid_neg, msg_neg = validate_model_predictions(neg_preds, expected_len=7)
        self.assertFalse(is_valid_neg)
        self.assertIn("negative", msg_neg)

    def test_generate_bounded_forecast_produces_continuous_future_dates(self) -> None:
        fake_model = MagicMock(spec=RandomForestRegressor)
        fake_model.predict.return_value = np.array([10.5])

        last_known_date = date(2026, 10, 10)
        horizon = 7
        forecast_entries = generate_bounded_forecast(
            model=fake_model,
            sku="SKU-PROD-001",
            last_date=last_known_date,
            recent_lags=[10.0, 12.0],
            horizon_days=horizon,
        )

        self.assertEqual(len(forecast_entries), horizon)
        for i, item in enumerate(forecast_entries):
            expected_date = last_known_date + timedelta(days=i + 1)
            self.assertEqual(item["date"], expected_date.isoformat())
            self.assertGreaterEqual(item["predictedUnits"], 0.0)

    def test_generate_bounded_forecast_fallback_on_exception_or_none_model(self) -> None:
        last_known_date = date(2026, 10, 10)
        # Model raises exception
        bad_model = MagicMock()
        bad_model.predict.side_effect = RuntimeError("inference failed")
        res_exc = generate_bounded_forecast(bad_model, "SKU-01", last_known_date, [10.0, 20.0], 3)
        self.assertEqual(len(res_exc), 3)

        # Model has no predict
        res_no_predict = generate_bounded_forecast(object(), "SKU-01", last_known_date, [10.0, 20.0], 3)
        self.assertEqual(len(res_no_predict), 3)

        # Empty recent_lags
        res_empty_lags = generate_bounded_forecast(object(), "SKU-01", last_known_date, [], 3)
        self.assertEqual(len(res_empty_lags), 3)

    def test_evaluate_champion_safety_gate_strict_thresholds(self) -> None:
        # Initial baseline without prior model
        promoted, status = evaluate_champion_safety_gate(candidate_rmse=3.2, prior_rmse=None, max_acceptable_rmse=10.0)
        self.assertTrue(promoted)
        self.assertEqual(status, "PROMOTED_INITIAL_BASELINE")

        # Candidate exceeds unacceptable ceiling
        rejected_ceiling, status_ceil = evaluate_champion_safety_gate(candidate_rmse=12.5, prior_rmse=None, max_acceptable_rmse=10.0)
        self.assertFalse(rejected_ceiling)
        self.assertEqual(status_ceil, "REJECTED_EXCEEDS_MAX_RMSE")

        # Candidate within 2% margin of champion
        promoted_margin, _ = evaluate_champion_safety_gate(candidate_rmse=3.25, prior_rmse=3.20, tolerance=0.02)
        self.assertTrue(promoted_margin)

        # Candidate clearly degraded
        rejected_degraded, status_deg = evaluate_champion_safety_gate(candidate_rmse=4.50, prior_rmse=3.20, tolerance=0.02)
        self.assertFalse(rejected_degraded)
        self.assertEqual(status_deg, "REJECTED_DEGRADED")


if __name__ == "__main__":
    unittest.main()
