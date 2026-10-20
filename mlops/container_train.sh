#!/bin/sh
set -eu

if [ "$#" -eq 0 ]; then
  if [ -d /data/sales_parquet ] && [ -n "$(find /data/sales_parquet -maxdepth 1 -name 'date=*' 2>/dev/null)" ]; then
    set -- --input-parquet /data/sales_parquet
  else
    SYNTH_PATH="/data/synthetic_sales.csv"
    if ! python /app/generate_sample_sales.py --days 30 --output "$SYNTH_PATH" 2>/dev/null; then
      SYNTH_PATH="/tmp/synthetic_sales.csv"
      python /app/generate_sample_sales.py --days 30 --output "$SYNTH_PATH"
    fi
    set -- --input-csv "$SYNTH_PATH"
  fi
fi

exec python /app/train_demand_model.py "$@"
