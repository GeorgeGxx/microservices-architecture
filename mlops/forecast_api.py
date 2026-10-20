"""Serve seven-day SKU demand forecasts from the latest successful MLflow run."""

from __future__ import annotations

import os
import time
from datetime import date, datetime, timedelta, timezone
from functools import lru_cache
from pathlib import Path
from time import perf_counter
from typing import Annotated, Any

import jwt
import mlflow
import mlflow.sklearn
import pandas as pd
from fastapi import Depends, FastAPI, HTTPException
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from mlflow import MlflowClient
from model_invariants import clamp_predictions
from prometheus_client import (
    CONTENT_TYPE_LATEST,
    REGISTRY,
    Counter,
    Gauge,
    Histogram,
    generate_latest,
)
from sklearn.ensemble import RandomForestRegressor
from starlette.responses import Response


app = FastAPI(title="Demand Forecast API", version="1.0.0")
bearer = HTTPBearer(auto_error=False)
EXPERIMENT_NAME = os.getenv("MLFLOW_EXPERIMENT_NAME", "inventory-demand-forecast")
TRACKING_URI = os.getenv("MLFLOW_TRACKING_URI", "http://mlflow:5000")
SALES_DATA_PATH = Path(os.getenv("MLOPS_SALES_PATH", "/data/synthetic_sales.csv"))
HORIZON_DAYS = 7
REQUESTS = Counter(
    "demand_forecast_http_requests_total",
    "HTTP requests handled by the demand forecast API.",
    ["method", "path", "status"],
)
REQUEST_DURATION = Histogram(
    "demand_forecast_http_request_duration_seconds",
    "Demand forecast API request duration in seconds.",
    ["method", "path"],
)
LAST_SUCCESS = Gauge(
    "demand_forecast_last_success_unixtime",
    "Unix timestamp of the last successful forecast response.",
)
LAST_OBSERVED_SALE = Gauge(
    "demand_forecast_last_observed_sale_unixtime",
    "Unix timestamp of the latest date in the sales input file.",
)
MODEL_RMSE = Gauge(
    "demand_forecast_model_rmse",
    "Root Mean Squared Error of the active demand forecast model.",
)
MODEL_MAE = Gauge(
    "demand_forecast_model_mae",
    "Mean Absolute Error of the active demand forecast model.",
)
MODEL_AGE_SECONDS = Gauge(
    "demand_forecast_model_age_seconds",
    "Age of the active demand forecast model in seconds since training.",
)


@app.get("/metrics")
@app.get("/metrics/")
def metrics() -> Response:
    return Response(content=generate_latest(REGISTRY), media_type=CONTENT_TYPE_LATEST)


@lru_cache(maxsize=2)
def jwks_client(uri: str) -> jwt.PyJWKClient:
    return jwt.PyJWKClient(uri)


@app.middleware("http")
async def record_http_metrics(request, call_next):
    started_at = perf_counter()
    response = await call_next(request)
    path = request.url.path
    if not path.startswith("/metrics"):
        REQUESTS.labels(request.method, path, str(response.status_code)).inc()
        REQUEST_DURATION.labels(request.method, path).observe(perf_counter() - started_at)
    return response


@lru_cache(maxsize=4)
def _load_model(model_uri: str) -> RandomForestRegressor:
    """Keep artifacts warm, while allowing a newly logged model to replace them."""
    return mlflow.sklearn.load_model(model_uri)


def require_admin(
    credentials: Annotated[HTTPAuthorizationCredentials | None, Depends(bearer)] = None,
) -> dict[str, Any]:
    """Validate the Keycloak access token and require the ADMIN realm role."""
    if credentials is None or credentials.scheme.lower() != "bearer":
        raise HTTPException(status_code=401, detail="Bearer token required")

    issuer = os.getenv(
        "KEYCLOAK_ISSUER", "http://localhost:8181/realms/microservices-realm"
    )
    jwks_uri = os.getenv(
        "KEYCLOAK_JWKS_URI",
        "http://keycloak:8181/realms/microservices-realm/protocol/openid-connect/certs",
    )
    allowed_issuers = {
        issuer.rstrip("/"),
        "http://localhost:8181/realms/microservices-realm",
        "http://127.0.0.1:8181/realms/microservices-realm",
        "http://keycloak.auth.svc.cluster.local/realms/microservices-realm",
        "http://keycloak.auth.svc.cluster.local:8181/realms/microservices-realm",
    }
    try:
        signing_key = jwks_client(jwks_uri).get_signing_key_from_jwt(credentials.credentials)
        claims = jwt.decode(
            credentials.credentials,
            signing_key.key,
            algorithms=["RS256"],
            options={"verify_aud": False},
        )
        token_issuer = str(claims.get("iss", "")).rstrip("/")
        if token_issuer not in allowed_issuers and not token_issuer.endswith("/realms/microservices-realm"):
            raise HTTPException(status_code=401, detail="Invalid token issuer")
    except (jwt.PyJWTError, jwt.PyJWKClientError) as exc:
        raise HTTPException(status_code=401, detail="Invalid or expired access token") from exc

    roles = claims.get("realm_access", {}).get("roles", [])
    if "ADMIN" not in roles and "admin" not in roles:
        raise HTTPException(status_code=403, detail="ADMIN role required")
    return claims


_ACTIVE_MODEL_ENTRY: tuple[RandomForestRegressor, str, datetime, float] | None = None
MODEL_CACHE_TTL_SEC = float(os.getenv("MLOPS_MODEL_CACHE_TTL_SEC", "60.0"))


def _select_champion_or_best_model(client: MlflowClient, experiment_id: str) -> tuple[Any, Any] | None:
    logged_models = client.search_logged_models(
        experiment_ids=[experiment_id],
        order_by=[{"field_name": "creation_time", "ascending": False}],
        max_results=100,
    )
    valid_models: list[tuple[Any, Any]] = []
    for logged_model in logged_models:
        if (
            logged_model.name != "demand-forecast"
            or logged_model.status.name != "READY"
            or not logged_model.source_run_id
        ):
            continue
        run = client.get_run(logged_model.source_run_id)
        if run.info.status != "FINISHED":
            continue
        valid_models.append((logged_model, run))
        if run.data.tags.get("model_role") == "champion":
            return logged_model, run
    return valid_models[0] if valid_models else None


def load_latest_model() -> tuple[RandomForestRegressor, str, datetime]:
    global _ACTIVE_MODEL_ENTRY
    now_mono = perf_counter()

    if _ACTIVE_MODEL_ENTRY is not None:
        cached_model, cached_run_id, cached_created, cached_at = _ACTIVE_MODEL_ENTRY
        if now_mono - cached_at < MODEL_CACHE_TTL_SEC:
            MODEL_AGE_SECONDS.set(max(0.0, (datetime.now(timezone.utc) - cached_created).total_seconds()))
            return cached_model, cached_run_id, cached_created

    try:
        mlflow.set_tracking_uri(TRACKING_URI)
        client = MlflowClient(tracking_uri=TRACKING_URI)
        experiment = client.get_experiment_by_name(EXPERIMENT_NAME)
        if experiment is None:
            if _ACTIVE_MODEL_ENTRY is not None:
                return _ACTIVE_MODEL_ENTRY[0], _ACTIVE_MODEL_ENTRY[1], _ACTIVE_MODEL_ENTRY[2]
            raise HTTPException(status_code=503, detail="No trained demand model is available yet")

        selected = _select_champion_or_best_model(client, experiment.experiment_id)
        if not selected:
            if _ACTIVE_MODEL_ENTRY is not None:
                return _ACTIVE_MODEL_ENTRY[0], _ACTIVE_MODEL_ENTRY[1], _ACTIVE_MODEL_ENTRY[2]
            raise HTTPException(status_code=503, detail="No successfully completed demand model is available")

        chosen_logged_model, chosen_run = selected
        model = _load_model(chosen_logged_model.model_uri)
        created = datetime.fromtimestamp(
            chosen_logged_model.creation_timestamp / 1000, tz=timezone.utc
        )
        run_metrics = chosen_run.data.metrics or {}
        rmse_val = run_metrics.get("rmse")
        mae_val = run_metrics.get("mae")

        if rmse_val is not None:
            MODEL_RMSE.set(rmse_val)
        if mae_val is not None:
            MODEL_MAE.set(mae_val)
        MODEL_AGE_SECONDS.set(max(0.0, (datetime.now(timezone.utc) - created).total_seconds()))

        _ACTIVE_MODEL_ENTRY = (model, chosen_run.info.run_id, created, now_mono)
        return model, chosen_run.info.run_id, created

    except HTTPException:
        raise
    except Exception as exc:
        if _ACTIVE_MODEL_ENTRY is not None:
            return _ACTIVE_MODEL_ENTRY[0], _ACTIVE_MODEL_ENTRY[1], _ACTIVE_MODEL_ENTRY[2]
        raise HTTPException(status_code=503, detail="Could not load the latest trained model") from exc


_DAILY_HISTORY_CACHE: tuple[pd.DataFrame, str, date, date, float, float] | None = None
HISTORY_CACHE_TTL_SEC = float(os.getenv("MLOPS_HISTORY_CACHE_TTL_SEC", "30.0"))


def _get_path_mtime(path: Path) -> float:
    try:
        return path.stat().st_mtime
    except OSError:
        return 0.0


def _read_sales_file(path: Path) -> pd.DataFrame:
    try:
        if path.is_dir() or path.suffix.lower() == ".parquet":
            return pd.read_parquet(path)
        return pd.read_csv(path)
    except (OSError, ValueError, ImportError) as exc:
        raise HTTPException(status_code=503, detail="Could not read the sales data") from exc


def _clean_and_aggregate_sales(sales: pd.DataFrame, file_stem: str) -> tuple[pd.DataFrame, str]:
    required = {"date", "product_id", "units_sold"}
    if not required.issubset(sales.columns):
        raise HTTPException(status_code=422, detail="Sales data requires date, product_id, and units_sold columns")
    sales["date"] = pd.to_datetime(sales["date"], errors="coerce").dt.date
    sales["units_sold"] = pd.to_numeric(sales["units_sold"], errors="coerce")
    sales = sales.dropna(subset=["date", "product_id", "units_sold"])
    sales = sales[sales["units_sold"] >= 0]
    if "order_number" in sales.columns:
        sales = sales.drop_duplicates(subset=["order_number", "product_id"])
    if sales.empty:
        raise HTTPException(status_code=422, detail="Sales data has no usable dated rows")

    # Bound historical depth to the most recent 90 days for inference efficiency
    max_history_date = sales["date"].max()
    min_cutoff = max_history_date - timedelta(days=90)
    sales = sales[sales["date"] >= min_cutoff]

    aggregated = (
        sales.groupby(["date", "product_id"], as_index=False)["units_sold"]
        .sum()
        .rename(columns={"product_id": "sku"})
    )
    source = "captured-sales"
    if "synthetic" in file_stem.lower() or (
        "order_number" in sales.columns and sales["order_number"].astype(str).str.startswith("SYNTH-").all()
    ):
        source = "synthetic"

    return aggregated, source


def _daily_history() -> tuple[pd.DataFrame, str, date, date]:
    global _DAILY_HISTORY_CACHE
    if not SALES_DATA_PATH.exists():
        raise HTTPException(status_code=503, detail=f"Sales data is missing: {SALES_DATA_PATH.name}")

    now_mono = perf_counter()
    current_mtime = _get_path_mtime(SALES_DATA_PATH)
    if _DAILY_HISTORY_CACHE is not None:
        cached_df, cached_source, cached_min, cached_max, cached_at, cached_mtime = _DAILY_HISTORY_CACHE
        if now_mono - cached_at < HISTORY_CACHE_TTL_SEC and cached_mtime == current_mtime:
            return cached_df, cached_source, cached_min, cached_max

    sales = _read_sales_file(SALES_DATA_PATH)
    aggregated, source = _clean_and_aggregate_sales(sales, SALES_DATA_PATH.stem)

    min_date = min(aggregated["date"])
    max_date = max(aggregated["date"])
    _DAILY_HISTORY_CACHE = (aggregated, source, min_date, max_date, now_mono, current_mtime)
    return aggregated, source, min_date, max_date


def _forecast_product(
    model: RandomForestRegressor, history: pd.DataFrame, sku: str
) -> dict[str, Any]:
    product = history[history["sku"] == sku].sort_values("date")
    days_available = (product["date"].max() - product["date"].min()).days + 1
    if days_available < 8:
        return {
            "sku": sku,
            "status": "INSUFFICIENT_HISTORY",
            "historyDays": days_available,
            "forecasts": [],
            "totalUnits": None,
        }

    daily = product.set_index("date")["units_sold"].astype(float)
    daily = daily.reindex(pd.date_range(product["date"].min(), product["date"].max(), freq="D").date, fill_value=0.0)
    observed_dates = list(daily.index)
    observed_values = daily.to_numpy(dtype=float).tolist()
    predictions: list[dict[str, Any]] = []

    for _ in range(1, HORIZON_DAYS + 1):
        prediction_date = observed_dates[-1] + timedelta(days=1)
        # pyspark.sql.functions.dayofweek numbers Sunday=1 through Saturday=7.
        spark_day_of_week = ((prediction_date.weekday() + 1) % 7) + 1
        features = pd.DataFrame(
            [{
                "lag_1": observed_values[-1],
                "lag_7": observed_values[-7],
                "day_of_week": spark_day_of_week,
                "day_of_year": prediction_date.timetuple().tm_yday,
            }]
        )
        units = float(clamp_predictions(model.predict(features))[0])
        predictions.append({"date": prediction_date.isoformat(), "units": round(units, 1)})
        observed_dates.append(prediction_date)
        observed_values.append(units)

    return {
        "sku": sku,
        "status": "READY",
        "historyDays": days_available,
        "forecasts": predictions,
        "totalUnits": round(sum(item["units"] for item in predictions), 1),
    }


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "UP"}


@app.get("/info")
def info() -> dict[str, Any]:
    return {
        "service": "demand-forecast-service",
        "version": "1.0.0",
        "git_commit": os.getenv("GIT_COMMIT", "dev"),
        "environment": os.getenv("ENVIRONMENT", "dev"),
        "tracking_uri": TRACKING_URI,
        "experiment_name": EXPERIMENT_NAME,
    }


@app.get(
    "/api/forecast",
    responses={
        401: {"description": "Unauthorized - Missing or invalid Bearer token"},
        403: {"description": "Forbidden - ADMIN role required"},
        422: {"description": "Unprocessable Entity - Invalid sales data"},
        503: {"description": "Service Unavailable - Model or sales data unavailable"},
    },
)
def get_forecast(_: Annotated[dict[str, Any], Depends(require_admin)]) -> dict[str, Any]:
    """Return daily SKU predictions for seven days after the last observed date."""
    model, run_id, model_created_at = load_latest_model()
    history, source, first_date, last_date = _daily_history()
    LAST_SUCCESS.set(time.time())
    LAST_OBSERVED_SALE.set(
        datetime.combine(last_date, datetime.min.time(), tzinfo=timezone.utc).timestamp()
    )
    products = [
        _forecast_product(model, history, str(sku))
        for sku in sorted(history["sku"].unique())
    ]
    return {
        "horizonDays": HORIZON_DAYS,
        "dataSource": source,
        "generatedAt": datetime.now(timezone.utc).isoformat(),
        "modelRunId": run_id,
        "modelCreatedAt": model_created_at.isoformat(),
        "historyStartDate": first_date.isoformat(),
        "historyEndDate": last_date.isoformat(),
        "products": products,
    }
