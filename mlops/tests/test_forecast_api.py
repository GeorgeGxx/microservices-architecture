import tempfile
import unittest
from datetime import date, datetime, timedelta, timezone
from pathlib import Path
from unittest.mock import MagicMock, patch

import numpy as np
import pandas as pd
from sklearn.ensemble import RandomForestRegressor

import forecast_api


class ForecastApiTests(unittest.TestCase):
    def setUp(self) -> None:
        forecast_api._ACTIVE_MODEL_ENTRY = None
        forecast_api._DAILY_HISTORY_CACHE = None

    def test_health_endpoint(self) -> None:
        result = forecast_api.health()
        self.assertEqual(result, {"status": "UP"})

    def test_metrics_endpoint_exposes_ml_gauges(self) -> None:
        response = forecast_api.metrics()
        self.assertEqual(response.status_code, 200)
        body = response.body.decode("utf-8")
        self.assertIn("demand_forecast_model_rmse", body)
        self.assertIn("demand_forecast_model_mae", body)
        self.assertIn("demand_forecast_model_age_seconds", body)

    def test_forecast_product_insufficient_history(self) -> None:
        model = MagicMock(spec=RandomForestRegressor)
        history = pd.DataFrame([
            {"date": date(2026, 10, 1), "sku": "SKU-TEST", "units_sold": 5.0},
            {"date": date(2026, 10, 2), "sku": "SKU-TEST", "units_sold": 6.0},
            {"date": date(2026, 10, 3), "sku": "SKU-TEST", "units_sold": 7.0},
        ])
        result = forecast_api._forecast_product(model, history, "SKU-TEST")
        self.assertEqual(result["sku"], "SKU-TEST")
        self.assertEqual(result["status"], "INSUFFICIENT_HISTORY")
        self.assertEqual(result["forecasts"], [])
        self.assertIsNone(result["totalUnits"])

    def test_forecast_product_generates_seven_days(self) -> None:
        model = MagicMock(spec=RandomForestRegressor)
        model.predict.return_value = np.array([15.2])

        start = date(2026, 9, 1)
        rows = [
            {"date": start + timedelta(days=i), "sku": "SKU-VALID", "units_sold": float(10 + (i % 3))}
            for i in range(14)
        ]
        history = pd.DataFrame(rows)
        result = forecast_api._forecast_product(model, history, "SKU-VALID")

        self.assertEqual(result["sku"], "SKU-VALID")
        self.assertEqual(result["status"], "READY")
        self.assertEqual(len(result["forecasts"]), 7)
        self.assertIsNotNone(result["totalUnits"])
        self.assertEqual(result["historyDays"], 14)

    def test_daily_history_caching(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            csv_path = Path(temp_dir) / "test_sales.csv"
            df = pd.DataFrame([
                {"date": "2026-10-01", "product_id": "SKU-1", "units_sold": 10},
                {"date": "2026-10-02", "product_id": "SKU-1", "units_sold": 12},
            ])
            df.to_csv(csv_path, index=False)

            with patch.object(forecast_api, "SALES_DATA_PATH", csv_path):
                first_df, source1, _, _ = forecast_api._daily_history()
                self.assertIsNotNone(forecast_api._DAILY_HISTORY_CACHE)

                second_df, source2, _, _ = forecast_api._daily_history()
                self.assertIs(first_df, second_df)
                self.assertEqual(source1, source2)

    def test_model_cache_and_graceful_fallback(self) -> None:
        fake_model = MagicMock(spec=RandomForestRegressor)
        fake_created = datetime.now(timezone.utc)
        fake_run_id = "run-cached-12345"

        forecast_api._ACTIVE_MODEL_ENTRY = (fake_model, fake_run_id, fake_created, 100.0)

        with patch("forecast_api.MlflowClient", side_effect=Exception("MLflow connection refused")):
            model, run_id, created = forecast_api.load_latest_model()
            self.assertIs(model, fake_model)
            self.assertEqual(run_id, fake_run_id)
            self.assertEqual(created, fake_created)


if __name__ == "__main__":
    unittest.main()
