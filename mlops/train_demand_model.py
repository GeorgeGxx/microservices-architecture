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
import time
from datetime import date, timedelta
from pathlib import Path
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from pyspark.sql import DataFrame, SparkSession


MINIMUM_DATE_PARTITIONS = int(os.getenv("MLOPS_MIN_PARTITIONS", "9"))
CANDIDATE_STATE_FILENAME = "candidate-input.state"


def _collect_partition_dates(dataset_path: Path) -> list[date]:
    dates: list[date] = []
    for partition in dataset_path.iterdir():
        if not partition.is_dir() or not partition.name.startswith("date="):
            continue
        try:
            dates.append(date.fromisoformat(partition.name.removeprefix("date=")))
        except ValueError:
            continue
    return sorted(set(dates))


def _collect_parquet_files(dataset_path: Path) -> list[Path]:
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
    return sorted(parquet_files)


def snapshot_dataset(dataset_path: Path) -> tuple[list[date], str]:
    """Return valid date partitions and a fingerprint of committed Parquet files."""
    if not dataset_path.is_dir():
        return [], ""

    dates = _collect_partition_dates(dataset_path)
    parquet_files = _collect_parquet_files(dataset_path)
    if not parquet_files:
        return dates, ""

    fingerprint = hashlib.sha256()
    for path in parquet_files:
        metadata = path.stat(follow_symlinks=False)
        fingerprint.update(path.relative_to(dataset_path).as_posix().encode("utf-8"))
        fingerprint.update(b"\0")
        fingerprint.update(str(metadata.st_size).encode("ascii"))
        fingerprint.update(b"\0")
        fingerprint.update(str(metadata.st_mtime_ns).encode("ascii"))
        fingerprint.update(b"\n")

    return dates, fingerprint.hexdigest()


def evaluate_champion_candidate(
    candidate_rmse: float, prior_rmse: float | None, tolerance: float = 0.02
) -> tuple[bool, str]:
    """Determine whether a candidate model qualifies as champion."""
    from model_invariants import evaluate_champion_safety_gate
    return evaluate_champion_safety_gate(candidate_rmse, prior_rmse, tolerance=tolerance)


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
            csv_path = Path(input_csv).resolve()
            frame = spark.read.option("header", True).option("inferSchema", True).csv(str(csv_path))
        else:
            parquet_path = Path(input_parquet).resolve()
            partition_pattern = str(parquet_path / "date=*")
            import glob
            if glob.glob(partition_pattern):
                frame = spark.read.option("basePath", str(parquet_path)).parquet(partition_pattern)
            else:
                frame = spark.read.parquet(str(parquet_path))
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


def _resolve_input_format(input_csv: str | None, input_parquet: str | None) -> str:
    if input_csv:
        return "csv"
    if input_parquet:
        return "parquet"
    return "generated_sample"


def _read_candidate_state(candidate_path: Path) -> tuple[str, float]:
    if not candidate_path.is_file():
        return "", 0.0
    try:
        candidate_fingerprint, candidate_timestamp = candidate_path.read_text(encoding="ascii").splitlines()[:2]
        return candidate_fingerprint, float(candidate_timestamp)
    except (OSError, ValueError):
        return "", 0.0


def _is_within_stability_window(state_path: Path, fingerprint: str, stability_seconds: int) -> bool:
    if not stability_seconds:
        return False
    candidate_path = state_path.with_name(CANDIDATE_STATE_FILENAME)
    candidate_path.parent.mkdir(parents=True, exist_ok=True)
    candidate_fingerprint, candidate_since = _read_candidate_state(candidate_path)

    if candidate_fingerprint != fingerprint:
        temporary_candidate_path = candidate_path.with_name(f"{candidate_path.name}.tmp-{os.getpid()}")
        temporary_candidate_path.write_text(f"{fingerprint}\n{time.time():.6f}\n", encoding="ascii")
        os.replace(temporary_candidate_path, candidate_path)
        print(
            f"Sales Parquet changed; waiting for {stability_seconds} seconds without writes before auto-training.",
            flush=True,
        )
        return True

    stable_for = time.time() - candidate_since
    if stable_for < stability_seconds:
        remaining = math.ceil(stability_seconds - stable_for)
        print(
            f"Sales Parquet is still within its stability window; auto-training will retry in about {remaining} seconds.",
            flush=True,
        )
        return True
    return False


def _check_auto_training_readiness(
    auto: bool, input_parquet: str | None
) -> tuple[bool, Path | None, str | None, str | None]:
    """Check dataset readiness for auto-training."""
    if not auto:
        return True, None, None, input_parquet

    dataset_path = Path(input_parquet or os.getenv("MLOPS_SALES_PATH", "/data/sales_parquet")).resolve()
    state_path = Path(
        os.getenv(
            "MLOPS_TRAINING_STATE_PATH",
            "/data/checkpoints/auto-training/last-successful-input.sha256",
        )
    ).resolve()
    dates, fingerprint = snapshot_dataset(dataset_path)
    if not fingerprint:
        print(f"No Parquet sales files found in {dataset_path}; training will be retried later.", flush=True)
        return False, None, None, None
    if len(dates) < MINIMUM_DATE_PARTITIONS:
        print(
            f"Found {len(dates)} date partitions; at least {MINIMUM_DATE_PARTITIONS} are required. "
            "Training will be retried later.",
            flush=True,
        )
        return False, None, None, None
    if state_path.is_file() and state_path.read_text(encoding="ascii").strip() == fingerprint:
        state_path.with_name(CANDIDATE_STATE_FILENAME).unlink(missing_ok=True)
        print("Sales Parquet has not changed since the last successful training; skipping.", flush=True)
        return False, None, None, None

    stability_seconds = max(0, int(os.getenv("MLOPS_AUTO_TRAIN_STABILITY_SECONDS", "0")))
    if _is_within_stability_window(state_path, fingerprint, stability_seconds):
        return False, None, None, None

    print(
        f"Training from {len(dates)} date partitions ({dates[0]} through {dates[-1]}).",
        flush=True,
    )
    return True, state_path, fingerprint, str(dataset_path)


def _build_prior_runs_filter(base_filter: str, input_format: str | None) -> str:
    if not input_format:
        return base_filter
    return f"{base_filter} and params.input_format = '{input_format}'"


def _query_prior_champion_rmse(
    client: Any, experiment_name: str, input_format: str | None = None
) -> float | None:
    try:
        current_exp = client.get_experiment_by_name(experiment_name)
        if not current_exp:
            return None
        champion_filter = _build_prior_runs_filter(
            "attributes.status = 'FINISHED' and tags.model_role = 'champion'",
            input_format,
        )
        champion_runs = client.search_runs(
            experiment_ids=[current_exp.experiment_id],
            filter_string=champion_filter,
            order_by=["metrics.rmse ASC"],
            max_results=1,
        )
        if not champion_runs:
            fallback_filter = _build_prior_runs_filter(
                "attributes.status = 'FINISHED' and metrics.rmse > 0",
                input_format,
            )
            champion_runs = client.search_runs(
                experiment_ids=[current_exp.experiment_id],
                filter_string=fallback_filter,
                order_by=["metrics.rmse ASC"],
                max_results=1,
            )
        if champion_runs and "rmse" in champion_runs[0].data.metrics:
            return float(champion_runs[0].data.metrics["rmse"])
    except Exception as eval_exc:
        print(f"Warning: could not evaluate prior champion metrics: {eval_exc}", flush=True)
    return None


def _log_champion_evaluation(
    mlflow: Any, rmse: float, mae: float, best_prior_rmse: float | None
) -> tuple[bool, str]:
    mlflow.log_metric("rmse", rmse)
    mlflow.log_metric("mae", mae)

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

    role = "champion" if is_champion else "challenger_rejected"
    mlflow.set_tag("model_role", role)
    mlflow.set_tag("promotion_status", promotion_status)
    mlflow.log_metric("is_champion", 1 if is_champion else 0)
    if best_prior_rmse is not None:
        mlflow.log_metric("prior_champion_rmse", best_prior_rmse)
    return is_champion, role


def _record_completed_auto_state(auto: bool, state_path: Path | None, fingerprint: str | None) -> None:
    if not (auto and state_path and fingerprint):
        return
    state_path.parent.mkdir(parents=True, exist_ok=True)
    temporary_state_path = state_path.with_name(f"{state_path.name}.tmp-{os.getpid()}")
    temporary_state_path.write_text(fingerprint + "\n", encoding="ascii")
    os.replace(temporary_state_path, state_path)
    state_path.with_name(CANDIDATE_STATE_FILENAME).unlink(missing_ok=True)
    print("Training completed; the dataset fingerprint was recorded.", flush=True)


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
        "--max-staleness-days",
        type=int,
        default=int(os.getenv("MLOPS_MAX_SALES_STALENESS_DAYS", "7")),
        help="Maximum allowed age in days of latest sales record before failing the quality gate (default: 7)",
    )
    parser.add_argument(
        "--auto",
        action="store_true",
        help="Check dataset readiness (partitions >= 9 and sha256 drift) before training",
    )
    args = parser.parse_args()

    should_proceed, state_path, fingerprint, resolved_parquet = _check_auto_training_readiness(
        args.auto, args.input_parquet
    )
    if not should_proceed:
        return 0
    if resolved_parquet:
        args.input_parquet = resolved_parquet

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

        from data_contracts import validate_spark_sales_dataframe

        quality = validate_spark_sales_dataframe(
            sales,
            max_staleness_days=args.max_staleness_days,
            min_history_days=int(os.getenv("MLOPS_MIN_HISTORY_DAYS", "8")),
            max_units_per_row=float(os.getenv("MLOPS_MAX_UNITS_PER_ROW", "50000")),
        )
        print(
            f"Sales quality gate: {'PASS' if quality['passed'] else 'FAIL'} | "
            f"{quality['rows_count']} rows | {quality['min_date']} to {quality['max_date']} | "
            f"freshness {quality['staleness_days']}d",
            flush=True,
        )
        if not quality["passed"]:
            raise ValueError("Sales quality gate failed: " + "; ".join(quality["violations"]))

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
            input_format = _resolve_input_format(args.input_csv, args.input_parquet)
            mlflow.log_param("algorithm", "sklearn_random_forest_with_spark_features")
            mlflow.log_param("num_trees", 40)
            mlflow.log_param("input_format", input_format)
            mlflow.log_param("input_path", args.input_csv or args.input_parquet or "generated_sample")
            mlflow.log_param("tracking_uri", tracking_uri)
            model = SklearnRandomForestRegressor(
                n_estimators=40,
                max_depth=6,
                min_samples_leaf=1,
                max_features="sqrt",
                random_state=42,
            )
            model.fit(train_pdf[feature_columns], train_pdf["units_sold"])
            predictions = model.predict(test_pdf[feature_columns])
            residuals = predictions - test_pdf["units_sold"].to_numpy()
            rmse = float(np.sqrt(np.mean(np.square(residuals))))
            mae = float(np.mean(np.abs(residuals)))

            client = mlflow.tracking.MlflowClient(tracking_uri=tracking_uri)
            best_prior_rmse = _query_prior_champion_rmse(client, args.experiment, input_format)
            _, role = _log_champion_evaluation(mlflow, rmse, mae, best_prior_rmse)

            mlflow.sklearn.log_model(
                model,
                name="demand-forecast",
                serialization_format="skops",
                skops_trusted_types=["sklearn.tree._tree.Tree"],
            )
            print(f"Run ID: {run.info.run_id}")
            print(f"Experiment: {args.experiment}")
            print(f"Role: {role} | RMSE: {rmse:.3f} | MAE: {mae:.3f}")
            print(f"MLflow UI: {os.getenv('MLFLOW_UI_URL', tracking_uri)}")

        _record_completed_auto_state(args.auto, state_path, fingerprint)
        return 0
    finally:
        spark.stop()


if __name__ == "__main__":
    raise SystemExit(main())
