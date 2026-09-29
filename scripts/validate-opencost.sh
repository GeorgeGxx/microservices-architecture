#!/usr/bin/env bash
set -euo pipefail

helm repo add opencost https://opencost.github.io/opencost-helm-chart
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

helm template opencost opencost/opencost \
  --version 2.5.32 \
  --namespace opencost \
  --values helm/values/opencost-minikube.yaml >/dev/null

helm template opencost opencost/opencost \
  --version 2.5.32 \
  --namespace opencost \
  --values helm/values/opencost-cloud.yaml >/dev/null

helm template prometheus prometheus-community/prometheus \
  --version 29.35.0 \
  --namespace observability \
  --values helm/values/prometheus-cloud.yaml >/dev/null

echo "OpenCost and cloud Prometheus Helm values rendered successfully."
