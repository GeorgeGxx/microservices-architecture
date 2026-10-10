"""Generate clearly labeled synthetic daily sales history for local MLOps runs."""

from __future__ import annotations

import argparse
import csv
import math
from datetime import date, timedelta
from pathlib import Path


DEFAULT_OUTPUT = Path(__file__).resolve().parent / "data" / "synthetic_sales.csv"
PRODUCT_BASELINES = {
    "LAPTOP-PRO": 5,
    "000001": 18,
    "000002": 14,
    "000003": 9,
}
CSV_COLUMNS = ["date", "product_id", "units_sold", "order_number"]


def generate_rows(days: int) -> list[dict[str, str | int]]:
    """Create one deterministic daily aggregate for each product and date."""
    first_day = date.today() - timedelta(days=days - 1)
    rows: list[dict[str, str | int]] = []

    for product_index, (product_id, baseline) in enumerate(PRODUCT_BASELINES.items()):
        for day_index in range(days):
            current_day = first_day + timedelta(days=day_index)
            weekday_effect = 3 if current_day.weekday() in (4, 5) else 0
            seasonal_effect = 3 * math.sin(2 * math.pi * day_index / 14)
            product_effect = (day_index * (product_index + 2)) % 4
            units_sold = max(1, round(baseline + weekday_effect + seasonal_effect + product_effect))
            rows.append(
                {
                    "date": current_day.isoformat(),
                    "product_id": product_id,
                    "units_sold": units_sold,
                    "order_number": f"SYNTH-{current_day:%Y%m%d}-{product_id}",
                }
            )
    return rows


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--days",
        type=int,
        default=30,
        help="Number of calendar days to generate (minimum 9 for lag features and a train/test split)",
    )
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT, help="Output CSV path")
    parser.add_argument("--kafka-bootstrap-servers", default="", help="If provided, publishes DELIVERED OrderEvents directly to Kafka")
    parser.add_argument("--kafka-topic", default="orders-topic", help="Kafka topic for OrderEvents (default: orders-topic)")
    args = parser.parse_args()

    if args.days < 9:
        parser.error("--days must be at least 9 to create lag features and non-empty train/test sets")

    rows = generate_rows(args.days)

    if args.kafka_bootstrap_servers:
        from kafka import KafkaProducer
        import json
        producer = KafkaProducer(
            bootstrap_servers=args.kafka_bootstrap_servers.split(","),
            value_serializer=lambda v: json.dumps(v).encode("utf-8"),
            key_serializer=lambda k: k.encode("utf-8"),
        )
        print(f"Publishing {len(rows)} order lines across {args.days} days directly to Kafka topic '{args.kafka_topic}' at {args.kafka_bootstrap_servers}...")
        for row in rows:
            event = {
                "orderNumber": str(row["order_number"]),
                "orderStatus": "DELIVERED",
                "customerName": "Historical Shopper",
                "shippingAddress": "Simulated Retail Route",
                "trackingNumber": f"TRK-{row['order_number']}",
                "totalAmount": float(row["units_sold"]) * 10.0,
                "userId": "historical-sim-user",
                "username": "admin_user",
                "occurredAt": f"{row['date']}T12:00:00Z",
                "orderCreatedAt": f"{row['date']}T10:00:00Z",
                "items": [
                    {
                        "sku": str(row["product_id"]),
                        "quantity": int(row["units_sold"]),
                    }
                ],
            }
            producer.send(args.kafka_topic, key=str(row["order_number"]), value=event)
        producer.flush()
        producer.close()
        print(f"Successfully published {len(rows)} DELIVERED order events across {args.days} distinct dates to Kafka!")
        return

    output = args.output.resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    with output.open("w", newline="", encoding="utf-8") as csv_file:
        writer = csv.DictWriter(csv_file, fieldnames=CSV_COLUMNS)
        writer.writeheader()
        writer.writerows(rows)

    first_date = rows[0]["date"]
    last_date = rows[-1]["date"]
    print(
        f"Generated {len(rows)} synthetic daily sales rows for {len(PRODUCT_BASELINES)} products "
        f"across {args.days} days ({first_date} to {last_date}) at {output}"
    )
    print("This file is synthetic training data; it does not modify captured Parquet data or publish Kafka events.")


if __name__ == "__main__":
    main()
