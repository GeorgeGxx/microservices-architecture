"""Model Invariants, Safety Clamping & Promotion Gating for MLOps."""

from __future__ import annotations

from datetime import date, timedelta
from typing import Any, Sequence

import numpy as np


def clamp_predictions(predictions: np.ndarray | Sequence[float], min_value: float = 0.0) -> np.ndarray:
    """Ensure all model predictions are non-negative, finite, and free of NaNs."""
    arr = np.asarray(predictions, dtype=float)
    # Replace NaN or Inf with min_value (safe fallback)
    arr = np.nan_to_num(arr, nan=min_value, posinf=min_value, neginf=min_value)
    return np.maximum(arr, min_value)


def validate_model_predictions(
    predictions: np.ndarray | Sequence[float], expected_len: int = 7
) -> tuple[bool, str]:
    """Validate that model outputs adhere to the production inferencing contract."""
    arr = np.asarray(predictions, dtype=float)
    if len(arr) != expected_len:
        return False, f"Prediction length mismatch: expected {expected_len}, got {len(arr)}"
    if np.any(np.isnan(arr)):
        return False, "Predictions contain NaN values"
    if np.any(np.isinf(arr)):
        return False, "Predictions contain infinite values"
    if np.any(arr < 0):
        return False, "Predictions contain negative demand quantities"
    return True, "OK"


def generate_bounded_forecast(
    model: Any,
    sku: str,
    last_date: date,
    recent_lags: Sequence[float],
    horizon_days: int = 7,
) -> list[dict[str, Any]]:
    """Generate a multi-step bounded forecast projecting continuous future dates."""
    forecasts = []
    # Base prediction seed from model or fallback
    raw_pred = 0.0
    if hasattr(model, "predict"):
        try:
            # Synthetic feature vector: [lag_1, lag_7, day_of_week, day_of_year]
            feature_vector = np.array([[recent_lags[0], recent_lags[-1], last_date.weekday(), last_date.timetuple().tm_yday]])
            raw_pred = float(model.predict(feature_vector)[0])
        except Exception:
            raw_pred = float(np.mean(recent_lags)) if len(recent_lags) > 0 else 0.0
    else:
        raw_pred = float(np.mean(recent_lags)) if len(recent_lags) > 0 else 0.0

    bounded_val = float(clamp_predictions(np.array([raw_pred]))[0])

    for day_offset in range(1, horizon_days + 1):
        target_date = last_date + timedelta(days=day_offset)
        # Apply gentle day-of-week modulation if weekend
        day_val = bounded_val * (1.15 if target_date.weekday() in (4, 5) else 1.0)
        forecasts.append({
            "sku": sku,
            "date": target_date.isoformat(),
            "predictedUnits": round(max(0.0, day_val), 1),
        })

    return forecasts


def evaluate_champion_safety_gate(
    candidate_rmse: float,
    prior_rmse: float | None,
    tolerance: float = 0.02,
    max_acceptable_rmse: float = 10.0,
) -> tuple[bool, str]:
    """Safety gate evaluating whether a newly trained candidate model is eligible for promotion."""
    if candidate_rmse > max_acceptable_rmse:
        return False, "REJECTED_EXCEEDS_MAX_RMSE"

    if prior_rmse is None:
        return True, "PROMOTED_INITIAL_BASELINE"

    # Candidate allowed if it improves or stays within allowed regression tolerance
    if candidate_rmse <= (prior_rmse * (1.0 + tolerance)):
        return True, "PROMOTED_IMPROVED_OR_COMPARABLE"

    return False, "REJECTED_DEGRADED"
