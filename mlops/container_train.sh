#!/bin/sh
set -eu

if [ "$#" -eq 0 ]; then
  if [ ! -s /data/synthetic_sales.csv ]; then
    python /app/generate_sample_sales.py --days 30 --output /data/synthetic_sales.csv
  fi
  set -- --input-csv /data/synthetic_sales.csv
fi

exec python /app/train_demand_model.py "$@"
