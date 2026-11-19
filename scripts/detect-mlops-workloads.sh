#!/usr/bin/env bash
set -euo pipefail

EVENT_NAME="${1:?event name required}"
BASE_REF="${2:-}"
HEAD_REF="${3:-HEAD}"
REQUESTED_WORKLOAD="${4:-all}"
ALL_WORKLOADS=(demand-forecast mlops-training mlflow)

append_workload() {
	local workload="$1"
	local existing
	for existing in "${workloads[@]:-}"; do
		[[ "$existing" == "$workload" ]] && return
	done
	workloads+=("$workload")
}

if [[ "$EVENT_NAME" == "workflow_dispatch" ]]; then
	if [[ "$REQUESTED_WORKLOAD" == "all" ]]; then
		printf '%s\n' "${ALL_WORKLOADS[@]}" | jq -Rsc 'split("\n") | map(select(length > 0))'
	else
		case "$REQUESTED_WORKLOAD" in
			demand-forecast|mlops-training|mlflow) printf '["%s"]\n' "$REQUESTED_WORKLOAD" ;;
			*) echo "Invalid MLOps workload: $REQUESTED_WORKLOAD" >&2; exit 2 ;;
		esac
	fi
	exit 0
fi

if [[ -z "$BASE_REF" ]] || ! git cat-file -e "${BASE_REF}^{commit}" 2>/dev/null; then
	echo "No valid base commit is available; selecting every MLOps workload." >&2
	printf '%s\n' "${ALL_WORKLOADS[@]}" | jq -Rsc 'split("\n") | map(select(length > 0))'
	exit 0
fi

workloads=()
while IFS= read -r file; do
	case "$file" in
		mlops/forecast_api.py|mlops/Dockerfile.forecast|mlops/tests/test_forecast_api.py)
			append_workload demand-forecast
			;;
		mlops/train_demand_model.py|mlops/capture_orders.py|mlops/container_train.sh|mlops/Dockerfile.training|mlops/requirements.container.txt|mlops/patch_spark_jars.py|mlops/tests/test_train_demand_model.py|mlops/tests/test_capture_orders.py)
			append_workload mlops-training
			;;
		mlops/Dockerfile)
			append_workload mlflow
			;;
		mlops/data_contracts.py|mlops/feature_engineering.py|mlops/model_invariants.py|mlops/requirements.txt)
			append_workload demand-forecast
			append_workload mlops-training
			;;
		mlops/tests/test_data_contracts.py|mlops/tests/test_feature_engineering.py|mlops/tests/test_model_invariants.py)
			append_workload demand-forecast
			append_workload mlops-training
			;;
		mlops/*)
			# Unknown or shared MLOps input: run all workloads to avoid a missed dependency.
			workloads=("${ALL_WORKLOADS[@]}")
			break
			;;
	esac
done < <(git diff --name-only --diff-filter=ACMRTD "${BASE_REF}...${HEAD_REF}")

printf '%s\n' "${workloads[@]}" | jq -Rsc 'split("\n") | map(select(length > 0))'
