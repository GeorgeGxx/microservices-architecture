"""
CloudEvents 1.0 and strongly-typed domain event contracts for analytics-service.
Aligned with CNCF CloudEvents v1.0 and centralized schemas in contracts/events/.
"""

from typing import Any, Generic, List, Optional, TypeVar
from pydantic import BaseModel, Field

T = TypeVar("T")


class CloudEventEnvelope(BaseModel, Generic[T]):
    """CloudEvents 1.0 compliant specification envelope."""
    specversion: str = "1.0"
    id: str
    source: str
    type: str
    time: Optional[str] = None
    datacontenttype: Optional[str] = "application/json"
    data: Optional[T] = None


class OrderItemContract(BaseModel):
    sku: str
    quantity: int = 1
    unit_price: Optional[float] = Field(default=None, alias="unitPrice")


class OrderEventContract(BaseModel):
    model_config = {"populate_by_name": True, "extra": "ignore"}

    order_number: str = Field(alias="orderNumber")
    order_status: Optional[str] = Field(default=None, alias="orderStatus")
    items_count: Optional[int] = Field(default=1, alias="itemsCount")
    total_amount: Optional[float] = Field(default=0.0, alias="totalAmount")
    customer_email: Optional[str] = Field(default=None, alias="customerEmail")
    user_id: Optional[str] = Field(default=None, alias="userId")
    items: Optional[List[OrderItemContract]] = None


class PaymentEventContract(BaseModel):
    model_config = {"populate_by_name": True, "extra": "ignore"}

    event_type: Optional[str] = Field(default=None, alias="eventType")
    status: Optional[str] = None
    order_number: Optional[str] = Field(default=None, alias="orderNumber")
    amount: Optional[float] = 0.0
    currency: Optional[str] = "USD"
    payment_method: Optional[str] = Field(default=None, alias="paymentMethod")
    user_id: Optional[str] = Field(default=None, alias="userId")
    items_count: Optional[int] = Field(default=1, alias="itemsCount")
    error_code: Optional[str] = Field(default=None, alias="errorCode")


class FulfillmentEventContract(BaseModel):
    model_config = {"populate_by_name": True, "extra": "ignore"}

    event_type: Optional[str] = Field(default=None, alias="eventType")
    order_number: Optional[str] = Field(default=None, alias="orderNumber")
    carrier: Optional[str] = None
    tracking_number: Optional[str] = Field(default=None, alias="trackingNumber")
    reason: Optional[str] = None


def unpack_cloud_event(raw: dict[str, Any]) -> tuple[str, dict[str, Any], Optional[str]]:
    """
    Extracts (event_type, domain_payload, event_id) handling both CloudEvents 1.0 envelopes
    and flat legacy schema formats.
    """
    if not isinstance(raw, dict):
        return ("UNKNOWN", {}, None)

    event_id = raw.get("id")

    # CloudEvents 1.0 envelope
    if raw.get("specversion") == "1.0" and isinstance(raw.get("data"), dict):
        event_type = str(raw.get("type") or "UNKNOWN")
        return (event_type, raw["data"], event_id)

    # Flat schema
    event_type = str(
        raw.get("eventType")
        or raw.get("event_type")
        or raw.get("orderStatus")
        or raw.get("status")
        or "UNKNOWN"
    )
    return (event_type, raw, event_id)
