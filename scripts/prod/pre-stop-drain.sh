#!/usr/bin/env bash
# ==============================================================================
# 🛑 Kubernetes Container PreStop Hook & Graceful Traffic Drain
# ==============================================================================
# Purpose:
#   Eliminates HTTP 502/503 errors and Kafka message drops during rolling updates.
#   Allows Istio Service Mesh, Ingress Gateway and kube-proxy to detach the Pod IP
#   from active endpoints BEFORE the application terminates active connections.
#
# Usage (in Pod spec lifecycle):
#   lifecycle:
#     preStop:
#       exec:
#         command: ["/bin/bash", "scripts/prod/pre-stop-drain.sh"]
# ==============================================================================
set -Eeuo pipefail

DRAIN_SECONDS="${DRAIN_SECONDS:-12}"
APP_PORT="${APP_PORT:-8080}"
APP_NAME="${APP_NAME:-microservice}"

log() {
  echo -e "\033[1;33m[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] [PRE-STOP DRAIN] [${APP_NAME}]\033[0m $*"
}

log "Termination signal received by Kubelet. Starting graceful traffic drain window..."

# 1. Optionally mark readiness endpoint OUT_OF_SERVICE on Spring Boot Actuator
# If the service supports state mutation on its readiness probe:
if command -v curl >/dev/null 2>&1; then
  if curl -s -f -X POST "http://127.0.0.1:${APP_PORT}/actuator/health/readiness" \
      -H "Content-Type: application/json" \
      -d '{"status":"OUT_OF_SERVICE"}' >/dev/null 2>&1; then
    log "Readiness probe transitioned to OUT_OF_SERVICE."
  fi
fi

# 2. Controlled wait for Istio Envoy and kube-proxy to propagate endpoint removal
log "Waiting ${DRAIN_SECONDS}s for Ingress and Service Mesh to drain active connections..."
sleep "${DRAIN_SECONDS}"

log "Drain window complete. Proceeding with graceful application shutdown (SIGTERM)..."
exit 0
