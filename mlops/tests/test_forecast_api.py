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

    def test_require_admin_missing_or_invalid_bearer(self) -> None:
        from fastapi import HTTPException
        from fastapi.security import HTTPAuthorizationCredentials

        with self.assertRaises(HTTPException) as ctx:
            forecast_api.require_admin(None)
        self.assertEqual(ctx.exception.status_code, 401)

        invalid_scheme = HTTPAuthorizationCredentials(scheme="Basic", credentials="abc")
        with self.assertRaises(HTTPException) as ctx:
            forecast_api.require_admin(invalid_scheme)
        self.assertEqual(ctx.exception.status_code, 401)

    @patch("forecast_api.jwks_client")
    @patch("jwt.decode")
    def test_require_admin_valid_token(self, mock_jwt_decode, mock_jwks_client) -> None:
        from fastapi.security import HTTPAuthorizationCredentials

        mock_jwk = MagicMock()
        mock_jwk.key = "fake-key"
        mock_client = MagicMock()
        mock_client.get_signing_key_from_jwt.return_value = mock_jwk
        mock_jwks_client.return_value = mock_client

        mock_jwt_decode.return_value = {
            "iss": "http://localhost:8181/realms/microservices-realm",
            "realm_access": {"roles": ["ADMIN", "USER"]},
        }
        creds = HTTPAuthorizationCredentials(scheme="Bearer", credentials="token123")
        claims = forecast_api.require_admin(creds)
        self.assertIn("ADMIN", claims["realm_access"]["roles"])

    @patch("forecast_api.jwks_client")
    @patch("jwt.decode")
    def test_require_admin_forbidden_when_not_admin(self, mock_jwt_decode, mock_jwks_client) -> None:
        from fastapi import HTTPException
        from fastapi.security import HTTPAuthorizationCredentials

        mock_jwk = MagicMock()
        mock_jwk.key = "fake-key"
        mock_client = MagicMock()
        mock_client.get_signing_key_from_jwt.return_value = mock_jwk
        mock_jwks_client.return_value = mock_client

        mock_jwt_decode.return_value = {
            "iss": "http://localhost:8181/realms/microservices-realm",
            "realm_access": {"roles": ["USER"]},
        }
        creds = HTTPAuthorizationCredentials(scheme="Bearer", credentials="token123")
        with self.assertRaises(HTTPException) as ctx:
            forecast_api.require_admin(creds)
        self.assertEqual(ctx.exception.status_code, 403)

    def test_clean_and_aggregate_sales_validations(self) -> None:
        from fastapi import HTTPException

        bad_df = pd.DataFrame([{"wrong_col": 1}])
        with self.assertRaises(HTTPException) as ctx:
            forecast_api._clean_and_aggregate_sales(bad_df, "test")
        self.assertEqual(ctx.exception.status_code, 422)

        empty_df = pd.DataFrame(columns=["date", "product_id", "units_sold"])
        with self.assertRaises(HTTPException) as ctx:
            forecast_api._clean_and_aggregate_sales(empty_df, "test")
        self.assertEqual(ctx.exception.status_code, 422)

        valid_df = pd.DataFrame([
            {"date": "2026-10-01", "product_id": "SKU-A", "units_sold": 5, "order_number": "SYNTH-1", "kafka_timestamp": 100},
            {"date": "2026-10-01", "product_id": "SKU-A", "units_sold": 9, "order_number": "SYNTH-1", "kafka_timestamp": 200},
            {"date": "2026-10-02", "product_id": "SKU-A", "units_sold": 7, "order_number": "SYNTH-2", "kafka_timestamp": 300},
        ])
        agg, source = forecast_api._clean_and_aggregate_sales(valid_df, "real_sales")
        self.assertEqual(source, "synthetic")
        self.assertEqual(len(agg), 2)
        self.assertEqual(float(agg.loc[agg["date"] == date(2026, 10, 1), "units_sold"].iloc[0]), 9.0)

    def test_get_forecast_endpoint(self) -> None:
        fake_model = MagicMock(spec=RandomForestRegressor)
        fake_model.predict.return_value = np.array([12.0])
        created = datetime(2026, 10, 15, tzinfo=timezone.utc)

        start = date(2026, 9, 1)
        rows = [
            {"date": start + timedelta(days=i), "sku": "SKU-1", "units_sold": 10.0}
            for i in range(12)
        ]
        history = pd.DataFrame(rows)

        with patch("forecast_api.load_latest_model", return_value=(fake_model, "run-99", created)):
            with patch("forecast_api._daily_history", return_value=(history, "synthetic", date(2026, 9, 1), date(2026, 9, 12))):
                result = forecast_api.get_forecast({})
                self.assertEqual(result["modelRunId"], "run-99")
                self.assertEqual(result["dataSource"], "synthetic")
                self.assertEqual(result["horizonDays"], 7)
                self.assertEqual(len(result["products"]), 1)
                self.assertEqual(result["products"][0]["sku"], "SKU-1")

    def test_read_sales_file(self) -> None:
        from fastapi import HTTPException
        with tempfile.TemporaryDirectory() as temp_dir:
            csv_path = Path(temp_dir) / "test.csv"
            pd.DataFrame([{"date": "2026-10-01", "product_id": "SKU-1", "units_sold": 10}]).to_csv(csv_path, index=False)
            df = forecast_api._read_sales_file(csv_path)
            self.assertEqual(len(df), 1)

            parquet_path = Path(temp_dir) / "test.parquet"
            pd.DataFrame([{"date": "2026-10-01", "product_id": "SKU-1", "units_sold": 10}]).to_parquet(parquet_path, index=False)
            df_pq = forecast_api._read_sales_file(parquet_path)
            self.assertEqual(len(df_pq), 1)

            with self.assertRaises(HTTPException) as ctx:
                forecast_api._read_sales_file(Path(temp_dir) / "missing.csv")
            self.assertEqual(ctx.exception.status_code, 503)

    def test_get_path_mtime(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            base = Path(temp_dir)
            p = base / "file.txt"
            p.write_text("hello")
            self.assertGreater(forecast_api._get_path_mtime(p), 0.0)
            part_dir = base / "date=2026-10-20"
            part_dir.mkdir()
            (part_dir / "part.parquet").write_bytes(b"parquet")
            self.assertGreater(forecast_api._get_path_mtime(base), 0.0)
            self.assertEqual(forecast_api._get_path_mtime(base / "does_not_exist"), 0.0)

    def test_resolve_active_sales_path_and_format_preference(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            base = Path(temp_dir)
            synth_csv = base / "synthetic_sales.csv"
            synth_csv.write_text("date,product_id,units_sold\n2026-10-01,SKU-1,5\n")
            parquet_dir = base / "sales_parquet"
            parquet_dir.mkdir()
            for day in range(1, 10):
                (parquet_dir / f"date=2026-10-{day:02d}").mkdir()

            with patch.object(forecast_api, "SALES_DATA_PATH", synth_csv):
                resolved = forecast_api._resolve_active_sales_path()
                self.assertEqual(resolved, parquet_dir)
                self.assertEqual(forecast_api._infer_preferred_input_format(resolved), "parquet")

        client = MagicMock()
        csv_model = MagicMock(name="csv-model")
        csv_model.name = "demand-forecast"
        csv_model.status.name = "READY"
        csv_model.source_run_id = "run-csv"
        pq_model = MagicMock(name="pq-model")
        pq_model.name = "demand-forecast"
        pq_model.status.name = "READY"
        pq_model.source_run_id = "run-pq"

        csv_run = MagicMock()
        csv_run.info.status = "FINISHED"
        csv_run.data.tags = {"model_role": "champion"}
        csv_run.data.params = {"input_format": "csv"}

        pq_run = MagicMock()
        pq_run.info.status = "FINISHED"
        pq_run.data.tags = {"model_role": "challenger_rejected"}
        pq_run.data.params = {"input_format": "parquet"}

        client.search_logged_models.return_value = [pq_model, csv_model]
        client.get_run.side_effect = [pq_run, csv_run]
        selected = forecast_api._select_champion_or_best_model(client, "exp-1", "parquet")
        self.assertEqual(selected, (pq_model, pq_run))

        # Fallback to champion when no preferred format matches
        client.get_run.side_effect = [csv_run]
        client.search_logged_models.return_value = [csv_model]
        selected_fallback = forecast_api._select_champion_or_best_model(client, "exp-1", "parquet")
        self.assertEqual(selected_fallback, (csv_model, csv_run))

    def test_load_latest_model_experiment_none(self) -> None:
        from fastapi import HTTPException
        mock_client = MagicMock()
        mock_client.get_experiment_by_name.return_value = None
        with patch("forecast_api.MlflowClient", return_value=mock_client):
            with self.assertRaises(HTTPException) as ctx:
                forecast_api.load_latest_model()
            self.assertEqual(ctx.exception.status_code, 503)

    def test_load_latest_model_champion_found(self) -> None:
        mock_client = MagicMock()
        mock_exp = MagicMock()
        mock_exp.experiment_id = "exp-123"
        mock_client.get_experiment_by_name.return_value = mock_exp

        logged_model = MagicMock()
        logged_model.name = "demand-forecast"
        logged_model.status.name = "READY"
        logged_model.source_run_id = "run-champ"
        logged_model.model_uri = "models:/demand-forecast/1"
        logged_model.creation_timestamp = 1760000000000

        run = MagicMock()
        run.info.status = "FINISHED"
        run.info.run_id = "run-champ"
        run.data.tags = {"model_role": "champion"}
        run.data.metrics = {"rmse": 2.1, "mae": 1.5}

        mock_client.search_logged_models.return_value = [logged_model]
        mock_client.get_run.return_value = run

        fake_model = MagicMock(spec=RandomForestRegressor)
        with patch("forecast_api.MlflowClient", return_value=mock_client):
            with patch("forecast_api._load_model", return_value=fake_model):
                model, run_id, created = forecast_api.load_latest_model()
                self.assertIs(model, fake_model)
                self.assertEqual(run_id, "run-champ")

    @patch("forecast_api.jwks_client")
    @patch("jwt.decode")
    def test_require_admin_invalid_issuer(self, mock_jwt_decode, mock_jwks_client) -> None:
        from fastapi import HTTPException
        from fastapi.security import HTTPAuthorizationCredentials

        mock_jwk = MagicMock()
        mock_jwk.key = "fake-key"
        mock_client = MagicMock()
        mock_client.get_signing_key_from_jwt.return_value = mock_jwk
        mock_jwks_client.return_value = mock_client

        mock_jwt_decode.return_value = {
            "iss": "http://malicious-issuer.com/realms/other",
            "realm_access": {"roles": ["ADMIN"]},
        }
        creds = HTTPAuthorizationCredentials(scheme="Bearer", credentials="token123")
        with self.assertRaises(HTTPException) as ctx:
            forecast_api.require_admin(creds)
        self.assertEqual(ctx.exception.status_code, 401)

    @patch("forecast_api.jwks_client")
    @patch("jwt.decode", side_effect=forecast_api.jwt.InvalidTokenError("expired"))
    def test_require_admin_rejects_invalid_jwt_signature(self, mock_jwt_decode, mock_jwks_client) -> None:
        from fastapi import HTTPException
        from fastapi.security import HTTPAuthorizationCredentials

        mock_jwks_client.return_value.get_signing_key_from_jwt.return_value.key = "fake-key"
        credentials = HTTPAuthorizationCredentials(scheme="Bearer", credentials="expired-token")
        with self.assertRaises(HTTPException) as ctx:
            forecast_api.require_admin(credentials)
        self.assertEqual(ctx.exception.status_code, 401)
        self.assertEqual(ctx.exception.detail, "Invalid or expired access token")

    def test_select_champion_skips_unready_and_unfinished_models(self) -> None:
        client = MagicMock()
        wrong_name = MagicMock(name="wrong-model")
        wrong_name.name = "other-model"
        pending = MagicMock(name="pending-model")
        pending.name = "demand-forecast"
        pending.status.name = "PENDING"
        no_source = MagicMock(name="no-source-model")
        no_source.name = "demand-forecast"
        no_source.status.name = "READY"
        no_source.source_run_id = None
        unfinished = MagicMock(name="unfinished-model")
        unfinished.name = "demand-forecast"
        unfinished.status.name = "READY"
        unfinished.source_run_id = "unfinished-run"
        finished = MagicMock(name="finished-model")
        finished.name = "demand-forecast"
        finished.status.name = "READY"
        finished.source_run_id = "finished-run"
        finished_run = MagicMock()
        finished_run.info.status = "FINISHED"
        finished_run.data.tags = {"model_role": "challenger"}
        client.search_logged_models.return_value = [wrong_name, pending, no_source, unfinished, finished]
        client.get_run.side_effect = [MagicMock(info=MagicMock(status="FAILED")), finished_run]

        selected = forecast_api._select_champion_or_best_model(client, "experiment-1")

        self.assertEqual(selected, (finished, finished_run))
        self.assertEqual(client.get_run.call_count, 2)

    def test_load_latest_model_without_usable_candidate_returns_503(self) -> None:
        from fastapi import HTTPException

        client = MagicMock()
        client.get_experiment_by_name.return_value.experiment_id = "exp-1"
        client.search_logged_models.return_value = []
        with patch("forecast_api.MlflowClient", return_value=client):
            with self.assertRaises(HTTPException) as ctx:
                forecast_api.load_latest_model()
        self.assertEqual(ctx.exception.status_code, 503)

    def test_load_latest_model_error_without_cached_model_returns_503(self) -> None:
        from fastapi import HTTPException

        with patch("forecast_api.MlflowClient", side_effect=RuntimeError("offline")):
            with self.assertRaises(HTTPException) as ctx:
                forecast_api.load_latest_model()
        self.assertEqual(ctx.exception.status_code, 503)

    def test_load_latest_model_fallback_to_active_when_empty(self) -> None:
        fake_model = MagicMock(spec=RandomForestRegressor)
        fake_created = datetime.now(timezone.utc)
        forecast_api._ACTIVE_MODEL_ENTRY = (fake_model, "active-run", fake_created, 0.0)

        mock_client = MagicMock()
        mock_client.get_experiment_by_name.return_value = None
        with patch("forecast_api.MlflowClient", return_value=mock_client):
            model, run_id, _ = forecast_api.load_latest_model()
            self.assertIs(model, fake_model)
            self.assertEqual(run_id, "active-run")

    def test_clean_sales_empty_after_negative_filter(self) -> None:
        from fastapi import HTTPException
        negative_df = pd.DataFrame([
            {"date": "2026-10-01", "product_id": "SKU-A", "units_sold": -5},
        ])
        with self.assertRaises(HTTPException) as ctx:
            forecast_api._clean_and_aggregate_sales(negative_df, "test")
        self.assertEqual(ctx.exception.status_code, 422)

    def test_daily_history_missing_sales_file_returns_503(self) -> None:
        from fastapi import HTTPException

        missing_file = Path("definitely-missing-sales.csv")
        with patch.object(forecast_api, "SALES_DATA_PATH", missing_file):
            with self.assertRaises(HTTPException) as ctx:
                forecast_api._daily_history()
        self.assertEqual(ctx.exception.status_code, 503)

    def test_read_sales_file_reports_unreadable_input(self) -> None:
        from fastapi import HTTPException

        with patch("forecast_api.pd.read_csv", side_effect=OSError("permission denied")):
            with self.assertRaises(HTTPException) as ctx:
                forecast_api._read_sales_file(Path("sales.csv"))
        self.assertEqual(ctx.exception.status_code, 503)

    def test_info_and_helper_caches_and_middleware(self) -> None:
        import asyncio

        info_payload = forecast_api.info()
        self.assertEqual(info_payload["service"], "demand-forecast-service")
        self.assertEqual(info_payload["version"], "1.0.0")

        # Exercise warm cache hit in load_latest_model
        fake_model = MagicMock(spec=RandomForestRegressor)
        fake_created = datetime.now(timezone.utc)
        forecast_api._ACTIVE_MODEL_ENTRY = (fake_model, "cached-ttl-run", fake_created, forecast_api.perf_counter())
        model, run_id, created = forecast_api.load_latest_model()
        self.assertIs(model, fake_model)
        self.assertEqual(run_id, "cached-ttl-run")
        self.assertEqual(created, fake_created)

        # Exercise fallback to active model when _select_champion_or_best_model returns None
        forecast_api._ACTIVE_MODEL_ENTRY = (fake_model, "stale-run", fake_created, -1000.0)
        mock_client = MagicMock()
        mock_client.get_experiment_by_name.return_value.experiment_id = "exp-1"
        with (
            patch("forecast_api.MlflowClient", return_value=mock_client),
            patch("forecast_api._select_champion_or_best_model", return_value=None),
        ):
            model2, run_id2, _ = forecast_api.load_latest_model()
            self.assertIs(model2, fake_model)
            self.assertEqual(run_id2, "stale-run")

        # Exercise jwks_client and _load_model wrappers
        forecast_api.jwks_client.cache_clear()
        with patch("forecast_api.jwt.PyJWKClient", return_value="jwk-client") as mock_pyjwk:
            self.assertEqual(forecast_api.jwks_client("http://keycloak/certs"), "jwk-client")
            mock_pyjwk.assert_called_once_with("http://keycloak/certs")

        forecast_api._load_model.cache_clear()
        with patch("forecast_api.mlflow.sklearn.load_model", return_value=fake_model) as mock_mlflow_load:
            self.assertIs(forecast_api._load_model("models:/demand-forecast/1"), fake_model)
            mock_mlflow_load.assert_called_once_with("models:/demand-forecast/1")

        # Exercise HTTP metrics middleware
        request = MagicMock()
        request.method = "GET"
        request.url.path = "/api/forecast"
        response = MagicMock()
        response.status_code = 200

        async def call_next(_req):
            return response

        returned = asyncio.run(forecast_api.record_http_metrics(request, call_next))
        self.assertIs(returned, response)


if __name__ == "__main__":
    unittest.main()
