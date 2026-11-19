import os

import sentry_sdk
from sentry_sdk.integrations.fastapi import FastApiIntegration


def _sanitize_event(event: dict, _hint: dict) -> dict:
    event.pop("request", None)
    event.pop("user", None)
    event.pop("contexts", None)
    event.pop("extra", None)
    event.pop("breadcrumbs", None)
    event.pop("message", None)
    event.pop("transaction", None)
    event["tags"] = {
        "service": "analytics-service",
        "environment": os.getenv("APP_ENV", os.getenv("ENVIRONMENT", "development")),
    }
    for exception in event.get("exception", {}).get("values", []):
        exception["value"] = "[redacted]"
        exception.pop("mechanism", None)
    return event


sentry_sdk.init(
    dsn=os.getenv("SENTRY_DSN") or None,
    environment=os.getenv("APP_ENV", os.getenv("ENVIRONMENT", "development")),
    release=os.getenv("APP_RELEASE", "unknown"),
    send_default_pii=False,
    max_breadcrumbs=0,
    traces_sample_rate=0.0,
    integrations=[FastApiIntegration()],
    before_send=_sanitize_event,
    before_breadcrumb=lambda _breadcrumb, _hint: None,
)
