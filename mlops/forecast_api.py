"""Serve seven-day SKU demand forecasts from the latest successful MLflow run."""

from __future__ import annotations

import os
import time
from datetime import date, datetime, timedelta, timezone
from functools import lru_cache
from pathlib import Path
from time import perf_counter
from typing import Any

import jwt
import mlflow
import mlflow.sklearn
import pandas as pd
from fastapi import Depends, FastAPI, HTTPException
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from mlflow import MlflowClient
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
    credentials: HTTPAuthorizationCredentials | None = Depends(bearer),
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
        "http://keycloak.auth.svc.cluster.local/realms/microservices-realm",
        "http://keycloak.auth.svc.cluster.local:8181/realms/microservices-realm",
    }
    try:
        signing_key = jwks_client(jwks_uri).get_signing_key_from_jwt(credentials.credentials)
        unverified = jwt.decode(
            credentials.credentials,
            options={"verify_signature": False, "verify_exp": False},
        )
        token_issuer = unverified.get("iss", "").rstrip("/")
        expected_issuer = token_issuer if token_issuer in allowed_issuers else issuer
        claims = jwt.decode(
            credentials.credentials,
            signing_key.key,
            algorithms=["RS256"],
            issuer=expected_issuer,
            options={"verify_aud": False},
        )
    except (jwt.PyJWTError, jwt.PyJWKClientError) as exc:
        raise HTTPException(status_code=401, detail="Invalid or expired access token") from exc

    roles = claims.get("realm_access", {}).get("roles", [])
    if "ADMIN" not in roles and "admin" not in roles:
        raise HTTPException(status_code=403, detail="ADMIN role required")
    return claims


def load_latest_model() -> tuple[RandomForestRegressor, str, datetime]:
    mlflow.set_tracking_uri(TRACKING_URI)
    client = MlflowClient(tracking_uri=TRACKING_URI)
    experiment = client.get_experiment_by_name(EXPERIMENT_NAME)
    if experiment is None:
        raise HTTPException(status_code=503, detail="No trained demand model is available yet")

    try:
        logged_models = client.search_logged_models(
            experiment_ids=[experiment.experiment_id],
            order_by=[{"field_name": "creation_time", "ascending": False}],
            max_results=100,
        )
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
            model = _load_model(logged_model.model_uri)
            created = datetime.fromtimestamp(
                logged_model.creation_timestamp / 1000, tz=timezone.utc
            )
            return model, run.info.run_id, created
    except HTTPException:
        raise
    except Exception as exc:  # MLflow reports transport and missing-artifact errors here.
        raise HTTPException(status_code=503, detail="Could not load the latest trained model") from exc

    raise HTTPException(status_code=503, detail="No successfully completed demand model is available")


def _daily_history() -> tuple[pd.DataFrame, str, date, date]:
    if not SALES_DATA_PATH.exists():
        raise HTTPException(status_code=503, detail=f"Sales data is missing: {SALES_DATA_PATH.name}")

    try:
        if SALES_DATA_PATH.is_dir() or SALES_DATA_PATH.suffix.lower() == ".parquet":
            sales = pd.read_parquet(SALES_DATA_PATH)
        else:
            sales = pd.read_csv(SALES_DATA_PATH)
    except (OSError, ValueError, ImportError, pd.errors.ParserError) as exc:
        raise HTTPException(status_code=503, detail="Could not read the sales data") from exc

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

    aggregated = (
        sales.groupby(["date", "product_id"], as_index=False)["units_sold"]
        .sum()
        .rename(columns={"product_id": "sku"})
    )
    source = "captured-sales"
    if "synthetic" in SALES_DATA_PATH.stem.lower():
        source = "synthetic"
    elif "order_number" in sales.columns:
        all_synthetic = sales["order_number"].astype(str).str.startswith("SYNTH-").all()
        if all_synthetic:
            source = "synthetic"
    return aggregated, source, min(aggregated["date"]), max(aggregated["date"])


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

    for offset in range(1, HORIZON_DAYS + 1):
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
        units = max(0.0, float(model.predict(features)[0]))
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


@app.get("/api/forecast")
def get_forecast(_: dict[str, Any] = Depends(require_admin)) -> dict[str, Any]:
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
