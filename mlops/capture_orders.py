"""Unified Kafka order capture pipeline supporting PySpark Parquet streaming and lightweight Python CSV ingestion."""

from __future__ import annotations

import argparse
import csv
import json
import os
import subprocess
import sys
import time
from datetime import datetime
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_CSV_OUTPUT = ROOT / "mlops" / "data" / "sales.csv"
CSV_COLUMNS = ["date", "product_id", "units_sold", "order_number"]


# -----------------------------------------------------------------------------
# Lightweight Python Engine (KafkaConsumer -> CSV)
# -----------------------------------------------------------------------------

def _kafka_python_config(bootstrap_servers: str) -> dict:
    return {
        "bootstrap_servers": bootstrap_servers,
        "group_id": os.getenv("KAFKA_MLOPS_GROUP_ID", "mlops-demand-history-v1"),
        "auto_offset_reset": "earliest",
        "enable_auto_commit": True,
        "auto_commit_interval_ms": 1000,
        "security_protocol": "PLAINTEXT",
    }


def _load_seen_orders(output: Path) -> set[str]:
    if not output.exists():
        return set()
    with output.open(newline="", encoding="utf-8") as csv_file:
        return {row["order_number"] for row in csv.DictReader(csv_file) if row.get("order_number")}


def _event_date(value: str) -> str:
    parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    return parsed.date().isoformat()


def _append_order_row(output: Path, event: dict, seen_orders: set[str]) -> int:
    order_number = event.get("orderNumber")
    occurred_at = event.get("orderCreatedAt") or event.get("occurredAt")
    items = event.get("items") or []
    if event.get("orderStatus") != "DELIVERED" or not order_number or not occurred_at or not items:
        return 0
    if order_number in seen_orders:
        return 0

    order_day = _event_date(occurred_at)
    rows = [
        {
            "date": order_day,
            "product_id": item["sku"],
            "units_sold": int(item["quantity"]),
            "order_number": order_number,
        }
        for item in items
        if item.get("sku") and item.get("quantity") is not None and int(item["quantity"]) > 0
    ]
    if not rows:
        return 0

    output.parent.mkdir(parents=True, exist_ok=True)
    needs_header = not output.exists() or output.stat().st_size == 0
    with output.open("a", newline="", encoding="utf-8") as csv_file:
        writer = csv.DictWriter(csv_file, fieldnames=CSV_COLUMNS)
        if needs_header:
            writer.writeheader()
        writer.writerows(rows)
        csv_file.flush()
        os.fsync(csv_file.fileno())
    seen_orders.add(order_number)
    return len(rows)


def run_python_capture(
    bootstrap_servers: str = "localhost:29092",
    topic: str = "orders-topic",
    output: Path = DEFAULT_CSV_OUTPUT,
    max_messages: int = 0,
) -> None:
    """Consume Kafka orders using pure Python kafka-python driver without JVM."""
    from kafka import KafkaConsumer

    resolved_output = output.resolve()
    seen_orders = _load_seen_orders(resolved_output)
    consumer = KafkaConsumer(topic, **_kafka_python_config(bootstrap_servers))
    records_read = 0
    rows_written = 0
    print(f"Capturing delivered-order lines from {topic} at {bootstrap_servers} into {resolved_output}", flush=True)
    print("Press Ctrl+C to stop. Older events without occurredAt/items are skipped.", flush=True)
    try:
        for message in consumer:
            records_read += 1
            if message.value is None:
                continue
            try:
                event = json.loads(message.value.decode("utf-8"))
                rows_written += _append_order_row(resolved_output, event, seen_orders)
            except (UnicodeDecodeError, json.JSONDecodeError, KeyError, TypeError, ValueError) as exc:
                print(f"Skipping invalid order event at partition={message.partition}, offset={message.offset}: {exc}", flush=True)
            if max_messages and records_read >= max_messages:
                break
    except KeyboardInterrupt:
        print("Stopping Kafka capture.", flush=True)
    finally:
        consumer.close()
    print(f"Read {records_read} Kafka records; appended {rows_written} sale lines.", flush=True)


# -----------------------------------------------------------------------------
# Distributed PySpark Engine (Structured Streaming -> Partitioned Parquet)
# -----------------------------------------------------------------------------

def run_spark_capture(
    bootstrap_servers: str = "kafka:9092",
    topic: str = "orders-topic",
    output: str = "/data/sales_parquet",
    checkpoint_location: str = "/data/checkpoints/sales_parquet",
    starting_offsets: str = "earliest",
    max_offsets_per_trigger: int = 1000,
) -> None:
    """Stream Kafka orders using PySpark Structured Streaming to partitioned Parquet."""
    from pyspark.sql import SparkSession
    from pyspark.sql import functions as F
    from pyspark.sql.types import ArrayType, IntegerType, StringType, StructField, StructType

    event_schema = StructType([
        StructField("orderNumber", StringType()),
        StructField("orderStatus", StringType()),
        StructField("occurredAt", StringType()),
        StructField("orderCreatedAt", StringType()),
        StructField("items", ArrayType(StructType([
            StructField("sku", StringType()),
            StructField("quantity", IntegerType()),
        ]))),
    ])

    spark = (SparkSession.builder.appName("orders-kafka-to-parquet")
             .master("local[*]")
             .config("spark.jars.packages", "org.apache.spark:spark-sql-kafka-0-10_2.12:3.5.9")
             .config("spark.jars.ivy", "/tmp/.ivy2")
             .getOrCreate())
    spark.sparkContext.setLogLevel("WARN")
    try:
        source = (spark.readStream.format("kafka")
                  .option("kafka.bootstrap.servers", bootstrap_servers)
                  .option("subscribe", topic)
                  .option("startingOffsets", starting_offsets)
                  .option("maxOffsetsPerTrigger", max_offsets_per_trigger)
                  .load())
        events = (source.select(
                    F.from_json(F.col("value").cast("string"), event_schema).alias("event"),
                    F.col("topic").alias("kafka_topic"), F.col("partition").alias("kafka_partition"),
                    F.col("offset").alias("kafka_offset"), F.col("timestamp").alias("kafka_timestamp"))
                  .select("event.*", "kafka_topic", "kafka_partition", "kafka_offset", "kafka_timestamp")
                  .where((F.upper("orderStatus") == "DELIVERED") & F.col("orderNumber").isNotNull())
                  .where(F.col("items").isNotNull()))
        lines = (events.select(
                    "orderNumber", "occurredAt", "orderCreatedAt", "kafka_topic", "kafka_partition",
                    "kafka_offset", "kafka_timestamp", F.explode("items").alias("item"))
                 .select(
                    F.coalesce(F.to_timestamp("orderCreatedAt"), F.to_timestamp("occurredAt")).alias("event_time"),
                    F.col("orderNumber").alias("order_number"), F.col("item.sku").alias("product_id"),
                    F.col("item.quantity").cast("integer").alias("units_sold"), "kafka_topic",
                    "kafka_partition", "kafka_offset", "kafka_timestamp")
                 .where(F.col("event_time").isNotNull() & F.col("product_id").isNotNull()
                        & (F.col("units_sold") > 0))
                 .withColumn("date", F.to_date("event_time"))
                 .select("date", "product_id", "units_sold", "order_number", "event_time",
                         "kafka_topic", "kafka_partition", "kafka_offset", "kafka_timestamp"))

        query = (lines.writeStream.format("parquet").outputMode("append")
                 .option("path", output)
                 .option("checkpointLocation", checkpoint_location)
                 .partitionBy("date")
                 .trigger(processingTime="10 seconds")
                 .start())
        print(f"Streaming {topic} from {bootstrap_servers} to Parquet at {output}", flush=True)
        print(f"Checkpoint: {checkpoint_location}. Stop with Ctrl+C.", flush=True)

        auto_train_interval = int(os.getenv("MLOPS_AUTO_TRAIN_INTERVAL_SEC", "30"))
        last_train_check = 0.0

        while query.isActive:
            time.sleep(5)
            now = time.time()
            if now - last_train_check >= auto_train_interval:
                last_train_check = now
                try:
                    subprocess.run(
                        [sys.executable, "/app/train_demand_model.py", "--auto"],
                        check=False,
                        timeout=300,
                    )
                except Exception as ex:
                    print(f"Auto-training invocation notice: {ex}", flush=True)

        query.awaitTermination()
    finally:
        spark.stop()


# -----------------------------------------------------------------------------
# CLI Entrypoints
# -----------------------------------------------------------------------------

def main_spark(argv: list[str] | None = None) -> None:
    parser = argparse.ArgumentParser(description="Stream delivered Kafka order lines into Parquet (PySpark engine).")
    parser.add_argument("--bootstrap-servers", default=os.getenv("KAFKA_BOOTSTRAP_SERVERS", "kafka:9092"))
    parser.add_argument("--topic", default="orders-topic")
    parser.add_argument("--output", default=os.getenv("MLOPS_SALES_PATH", "/data/sales_parquet"))
    parser.add_argument("--checkpoint-location", default="/data/checkpoints/sales_parquet")
    parser.add_argument("--starting-offsets", choices=("earliest", "latest"), default="earliest")
    parser.add_argument("--max-offsets-per-trigger", type=int, default=1000)
    args = parser.parse_args(argv)

    run_spark_capture(
        bootstrap_servers=args.bootstrap_servers,
        topic=args.topic,
        output=args.output,
        checkpoint_location=args.checkpoint_location,
        starting_offsets=args.starting_offsets,
        max_offsets_per_trigger=args.max_offsets_per_trigger,
    )


def main_python(argv: list[str] | None = None) -> None:
    parser = argparse.ArgumentParser(description="Capture delivered order lines into CSV (lightweight Python engine).")
    parser.add_argument("--bootstrap-servers", default=os.getenv("KAFKA_MLOPS_BOOTSTRAP_SERVERS", "localhost:29092"))
    parser.add_argument("--topic", default="orders-topic")
    parser.add_argument("--output", type=Path, default=DEFAULT_CSV_OUTPUT)
    parser.add_argument("--max-messages", type=int, default=0, help="Stop after this many Kafka records; 0 keeps listening")
    args = parser.parse_args(argv)

    run_python_capture(
        bootstrap_servers=args.bootstrap_servers,
        topic=args.topic,
        output=args.output,
        max_messages=args.max_messages,
    )


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--engine", choices=("spark", "python"), default="spark", help="Processing engine (spark for Parquet, python for lightweight CSV)")
    args, unknown = parser.parse_known_args()

    if args.engine == "python":
        main_python(unknown)
    else:
        main_spark(unknown)


if __name__ == "__main__":
    main()
