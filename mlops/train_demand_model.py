"""Prepare local product-demand features with PySpark and track training in MLflow.

By default the script creates deterministic sample sales data. Use --input-csv
or --input-parquet to train from captured order-line data.
"""

from __future__ import annotations

import argparse
import hashlib
import math
import os
import stat
from datetime import date, timedelta
from pathlib import Path
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from pyspark.sql import DataFrame, SparkSession


MINIMUM_DATE_PARTITIONS = int(os.getenv("MLOPS_MIN_PARTITIONS", "9"))


def snapshot_dataset(dataset_path: Path) -> tuple[list[date], str]:
    """Return valid date partitions and a fingerprint of committed Parquet files."""
    if not dataset_path.is_dir():
        return [], ""

    dates: list[date] = []
    for partition in dataset_path.iterdir():
        if not partition.is_dir() or not partition.name.startswith("date="):
            continue
        try:
            dates.append(date.fromisoformat(partition.name.removeprefix("date=")))
        except ValueError:
            continue

    fingerprint = hashlib.sha256()
    parquet_files: list[Path] = []
    for current_dir, _, filenames in os.walk(dataset_path, followlinks=False):
        dir_name = Path(current_dir).name
        if dir_name.startswith(("_", ".")):
            continue
        for filename in filenames:
            if filename.startswith(("_", ".")):
                continue
            path = Path(current_dir, filename)
            try:
                metadata = path.stat(follow_symlinks=False)
            except FileNotFoundError:
                continue
            if path.suffix == ".parquet" and stat.S_ISREG(metadata.st_mode):
                parquet_files.append(path)

    for path in sorted(parquet_files):
        metadata = path.stat(follow_symlinks=False)
        fingerprint.update(path.relative_to(dataset_path).as_posix().encode("utf-8"))
        fingerprint.update(b"\0")
        fingerprint.update(str(metadata.st_size).encode("ascii"))
        fingerprint.update(b"\0")
        fingerprint.update(str(metadata.st_mtime_ns).encode("ascii"))
        fingerprint.update(b"\n")

    return sorted(set(dates)), fingerprint.hexdigest() if parquet_files else ""


def evaluate_champion_candidate(
    candidate_rmse: float, prior_rmse: float | None, tolerance: float = 0.02
) -> tuple[bool, str]:
    """Determine whether a candidate model qualifies as champion."""
    if prior_rmse is None:
        return True, "PROMOTED_INITIAL_BASELINE"
    if candidate_rmse <= (prior_rmse * (1.0 + tolerance)):
        return True, "PROMOTED_IMPROVED_OR_COMPARABLE"
    return False, "REJECTED_DEGRADED"


def sample_sales(spark: SparkSession, days: int = 240) -> DataFrame:
    """Create reproducible daily sales for three example products."""
    rows = []
    start = date.today() - timedelta(days=days)
    for product_index, product_id in enumerate(("SKU-1001", "SKU-1002", "SKU-1003")):
        baseline = 12 + product_index * 5
        for day_index in range(days):
            current = start + timedelta(days=day_index)
            weekly_effect = (3 if current.weekday() in (4, 5) else 0)
            seasonal_effect = 4 * math.sin(2 * math.pi * day_index / 30)
            units_sold = max(0, round(baseline + weekly_effect + seasonal_effect + ((day_index * (product_index + 3)) % 5) - 2))
            rows.append((current.isoformat(), product_id, units_sold))
    return spark.createDataFrame(rows, ["date", "product_id", "units_sold"])


def read_sales(spark: SparkSession, input_csv: str | None, input_parquet: str | None) -> DataFrame:
    from pyspark.sql import functions as F

    if input_csv or input_parquet:
        if input_csv:
            frame = spark.read.option("header", True).option("inferSchema", True).csv(input_csv)
        else:
            import glob
            partition_pattern = os.path.join(input_parquet, "date=*")
            if glob.glob(partition_pattern):
                frame = spark.read.option("basePath", input_parquet).parquet(partition_pattern)
            else:
                frame = spark.read.parquet(input_parquet)
        required = {"date", "product_id", "units_sold"}
        missing = required.difference(frame.columns)
        if missing:
            raise ValueError(f"Input data is missing required columns: {', '.join(sorted(missing))}")
        if "order_number" in frame.columns:
            # Kafka may publish an order more than once as its status changes.
            frame = frame.dropDuplicates(["order_number", "product_id"])
        return frame.select(
            F.to_date("date").alias("date"), "product_id", F.col("units_sold").cast("double")
        )
    return sample_sales(spark)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    inputs = parser.add_mutually_exclusive_group()
    inputs.add_argument("--input-csv", help="CSV containing date, product_id, units_sold")
    inputs.add_argument("--input-parquet", help="Parquet dataset directory with date, product_id, units_sold")
    parser.add_argument(
        "--experiment",
        default=os.getenv("MLFLOW_EXPERIMENT_NAME", "inventory-demand-forecast"),
    )
    parser.add_argument(
        "--auto",
        action="store_true",
        help="Check dataset readiness (partitions >= 9 and sha256 drift) before training",
    )
    args = parser.parse_args()

    state_path: Path | None = None
    fingerprint: str | None = None
    if args.auto:
        dataset_path = Path(args.input_parquet or os.getenv("MLOPS_SALES_PATH", "/data/sales_parquet"))
        state_path = Path(
            os.getenv(
                "MLOPS_TRAINING_STATE_PATH",
                "/data/checkpoints/auto-training/last-successful-input.sha256",
            )
        )
        dates, fingerprint = snapshot_dataset(dataset_path)
        if not fingerprint:
            print(f"No Parquet sales files found in {dataset_path}; training will be retried later.", flush=True)
            return 0
        if len(dates) < MINIMUM_DATE_PARTITIONS:
            print(
                f"Found {len(dates)} date partitions; at least {MINIMUM_DATE_PARTITIONS} are required. "
                "Training will be retried later.",
                flush=True,
            )
            return 0
        if state_path.is_file():
            previous_fingerprint = state_path.read_text(encoding="ascii").strip()
            if previous_fingerprint == fingerprint:
                print("Sales Parquet has not changed since the last successful training; skipping.", flush=True)
                return 0

        print(
            f"Training from {len(dates)} date partitions ({dates[0]} through {dates[-1]}).",
            flush=True,
        )
        args.input_parquet = str(dataset_path)

    import mlflow
    import numpy as np
    from sklearn.ensemble import RandomForestRegressor as SklearnRandomForestRegressor
    from pyspark.sql import SparkSession, Window
    from pyspark.sql import functions as F

    tracking_uri = os.getenv("MLFLOW_TRACKING_URI", "http://127.0.0.1:5000")
    mlflow.set_tracking_uri(tracking_uri)
    mlflow.set_experiment(args.experiment)

    spark = SparkSession.builder.appName("inventory-demand-training").master("local[*]").getOrCreate()
    spark.sparkContext.setLogLevel("ERROR")
    try:
        sales = read_sales(spark, args.input_csv, args.input_parquet)
        required = {"date", "product_id", "units_sold"}
        missing = required.difference(sales.columns)
        if missing:
            raise ValueError(f"Input data is missing required columns: {', '.join(sorted(missing))}")

        # The generated sample uses ISO date strings, while CSV inference may
        # produce strings or dates. Normalize before sequence() builds the spine.
        sales = sales.withColumn("date", F.to_date("date"))
        if sales.isEmpty():
            raise ValueError("No usable sales rows were found in the selected input.")

        daily_sales = sales.groupBy("date", "product_id").agg(F.sum("units_sold").alias("units_sold"))
        product_ranges = daily_sales.groupBy("product_id").agg(
            F.min("date").alias("start_date"),
            F.max("date").alias("end_date"),
        )
        date_spine = product_ranges.select(
            "product_id",
            F.explode(
                F.sequence("start_date", "end_date", F.expr("INTERVAL 1 DAY"))
            ).alias("date"),
        )
        daily = (
            date_spine.join(daily_sales, on=["date", "product_id"], how="left")
            .select("date", "product_id", F.coalesce("units_sold", F.lit(0.0)).alias("units_sold"))
        )
        window = Window.partitionBy("product_id").orderBy("date")
        features = (
            daily.withColumn("lag_1", F.lag("units_sold", 1).over(window))
            .withColumn("lag_7", F.lag("units_sold", 7).over(window))
            .withColumn("day_of_week", F.dayofweek("date"))
            .withColumn("day_of_year", F.dayofyear("date"))
            .na.drop(subset=["lag_1", "lag_7"])
        )
        date_count = features.select("date").distinct().count()
        test_days = max(1, math.ceil(date_count * 0.2))
        test_start = (
            features.select("date")
            .distinct()
            .orderBy(F.col("date").desc())
            .limit(test_days)
            .agg(F.min("date"))
            .first()[0]
        )
        train = features.where(F.col("date") < F.lit(test_start))
        test = features.where(F.col("date") >= F.lit(test_start))
        if train.isEmpty() or test.isEmpty():
            raise ValueError("Need enough dated sales rows per product to create train and test sets.")

        feature_columns = ["lag_1", "lag_7", "day_of_week", "day_of_year"]
        train_pdf = train.select(*feature_columns, "units_sold").toPandas()
        test_pdf = test.select(*feature_columns, "units_sold").toPandas()

        with mlflow.start_run() as run:
            mlflow.log_param("algorithm", "sklearn_random_forest_with_spark_features")
            mlflow.log_param("num_trees", 40)
            mlflow.log_param("input_format", "csv" if args.input_csv else "parquet" if args.input_parquet else "generated_sample")
            mlflow.log_param("input_path", args.input_csv or args.input_parquet or "generated_sample")
            mlflow.log_param("tracking_uri", tracking_uri)
            model = SklearnRandomForestRegressor(n_estimators=40, max_depth=6, random_state=42)
            model.fit(train_pdf[feature_columns], train_pdf["units_sold"])
            predictions = model.predict(test_pdf[feature_columns])
            residuals = predictions - test_pdf["units_sold"].to_numpy()
            rmse = float(np.sqrt(np.mean(np.square(residuals))))
            mae = float(np.mean(np.abs(residuals)))
            # Champion vs Challenger Evaluation
            best_prior_rmse: float | None = None
            try:
                client = mlflow.tracking.MlflowClient(tracking_uri=tracking_uri)
                current_exp = client.get_experiment_by_name(args.experiment)
                if current_exp:
                    champion_runs = client.search_runs(
                        experiment_ids=[current_exp.experiment_id],
                        filter_string="attributes.status = 'FINISHED' and tags.model_role = 'champion'",
                        order_by=["metrics.rmse ASC"],
                        max_results=1,
                    )
                    if not champion_runs:
                        champion_runs = client.search_runs(
                            experiment_ids=[current_exp.experiment_id],
                            filter_string="attributes.status = 'FINISHED' and metrics.rmse > 0",
                            order_by=["metrics.rmse ASC"],
                            max_results=1,
                        )
                    if champion_runs and "rmse" in champion_runs[0].data.metrics:
                        best_prior_rmse = champion_runs[0].data.metrics["rmse"]
            except Exception as eval_exc:
                print(f"Warning: could not evaluate prior champion metrics: {eval_exc}", flush=True)

            is_champion, promotion_status = evaluate_champion_candidate(rmse, best_prior_rmse)
            if not is_champion:
                print(
                    f"Challenger model degraded: candidate RMSE {rmse:.3f} > prior champion RMSE {best_prior_rmse:.3f}. "
                    "Model tagged as challenger_rejected.",
                    flush=True,
                )
            else:
                status_text = (
                    f"(improved from {best_prior_rmse:.3f})"
                    if best_prior_rmse is not None
                    else "(baseline champion initialized)"
                )
                print(f"Candidate accepted as champion: RMSE {rmse:.3f} {status_text}.", flush=True)

            mlflow.set_tag("model_role", "champion" if is_champion else "challenger_rejected")
            mlflow.set_tag("promotion_status", promotion_status)
            mlflow.log_metric("is_champion", 1 if is_champion else 0)
            if best_prior_rmse is not None:
                mlflow.log_metric("prior_champion_rmse", best_prior_rmse)

            mlflow.sklearn.log_model(
                model,
                name="demand-forecast",
                serialization_format="skops",
                skops_trusted_types=["sklearn.tree._tree.Tree"],
            )
            print(f"Run ID: {run.info.run_id}")
            print(f"Experiment: {args.experiment}")
            print(f"Role: {'champion' if is_champion else 'challenger_rejected'} | RMSE: {rmse:.3f} | MAE: {mae:.3f}")
            print(f"MLflow UI: {os.getenv('MLFLOW_UI_URL', tracking_uri)}")

        if args.auto and state_path and fingerprint:
            state_path.parent.mkdir(parents=True, exist_ok=True)
            temporary_state_path = state_path.with_name(f"{state_path.name}.tmp-{os.getpid()}")
            temporary_state_path.write_text(fingerprint + "\n", encoding="ascii")
            os.replace(temporary_state_path, state_path)
            print("Training completed; the dataset fingerprint was recorded.", flush=True)
        return 0
    finally:
        spark.stop()


if __name__ == "__main__":
    raise SystemExit(main())
