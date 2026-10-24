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

log "Señal de terminación recibida por Kubelet. Iniciando periodo de drenado de tráfico..."

# 1. Deshabilitar opcionalmente el endpoint de readiness en Spring Boot Actuator
# Si el servicio soporta endpoint de desregistro o cambio de estado:
if command -v curl >/dev/null 2>&1; then
  if curl -s -f -X POST "http://127.0.0.1:${APP_PORT}/actuator/health/readiness" \
      -H "Content-Type: application/json" \
      -d '{"status":"OUT_OF_SERVICE"}' >/dev/null 2>&1; then
    log "Readiness probe cambiada exitosamente a OUT_OF_SERVICE."
  fi
fi

# 2. Espera controlada para que Istio Envoy y kube-proxy propaguen la baja del endpoint
log "Esperando ${DRAIN_SECONDS}s para que el Ingress y Service Mesh desconecten el tráfico activo..."
sleep "${DRAIN_SECONDS}"

log "Drenado completado. Procediendo con el apagado seguro de la aplicación (SIGTERM)..."
exit 0
