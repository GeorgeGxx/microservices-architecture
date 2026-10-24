#!/usr/bin/env bash
# ==============================================================================
# 🚀 Velero v1.18.3 Automated Production Cluster Deployment
# ==============================================================================
# Usage:
#   ./scripts/deploy-velero.sh [--cloud aws|azure|gcp|minikube] [--bucket <name>]
# ==============================================================================
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

CLOUD_TARGET="${1:-minikube}"
VELERO_NAMESPACE="velero"
CHART_VERSION="8.7.0" # Compatible con Velero 1.18.x

log() {
  echo -e "\033[1;34m[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] [INFO]\033[0m $*"
}
log_success() {
  echo -e "\033[1;32m[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] [SUCCESS]\033[0m $*"
}
log_warn() {
  echo -e "\033[1;33m[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] [WARN]\033[0m $*"
}
log_error() {
  echo -e "\033[1;31m[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] [ERROR]\033[0m $*" >&2
}

# 1. Validar Prerrequisitos
for cmd in kubectl helm; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    log_error "Comando requerido no encontrado: ${cmd}"
    exit 1
  fi
done

if ! command -v velero >/dev/null 2>&1; then
  log_warn "Velero CLI no encontrado. Instalando automáticamente v1.18.3..."
  "${SCRIPT_DIR}/install-velero.sh" v1.18.3
fi

log "Verificando conectividad con el cluster Kubernetes..."
kubectl cluster-info >/dev/null

# 2. Configurar repositorio Helm de Velero
log "Actualizando repositorio Helm de VMware Tanzu..."
helm repo add vmware-tanzu https://vmware-tanzu.github.io/helm-charts >/dev/null 2>&1 || true
helm repo update vmware-tanzu >/dev/null

# 3. Preparar Namespace
log "Asegurando namespace '${VELERO_NAMESPACE}'..."
kubectl create namespace "${VELERO_NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

# 4. Desplegar / Actualizar Velero v1.18.3
VALUES_FILE="k8s/common/bcdr/velero-values.yaml"
SCHEDULE_FILE="k8s/common/bcdr/velero-schedule.yaml"

if [[ ! -f "$VALUES_FILE" ]]; then
  if [[ -f "${SCRIPT_DIR}/../${VALUES_FILE}" ]]; then
    VALUES_FILE="${SCRIPT_DIR}/../${VALUES_FILE}"
    SCHEDULE_FILE="${SCRIPT_DIR}/../${SCHEDULE_FILE}"
  else
    log_error "No se encontró el archivo de valores: ${VALUES_FILE}"
    exit 1
  fi
fi

log "Desplegando Velero Server v1.18.3 (Chart version ~${CHART_VERSION})..."
helm upgrade --install velero vmware-tanzu/velero \
  --namespace "${VELERO_NAMESPACE}" \
  --version "${CHART_VERSION}" \
  -f "${VALUES_FILE}" \
  --wait \
  --timeout 7m

log "Esperando que el deployment de Velero esté listo..."
kubectl rollout status deployment/velero -n "${VELERO_NAMESPACE}" --timeout=120s

log "Esperando que el DaemonSet Node-Agent (Kopia) esté listo en todos los nodos..."
kubectl rollout status daemonset/node-agent -n "${VELERO_NAMESPACE}" --timeout=120s || true

# 5. Aplicar Schedule de Respaldo BCDR
if [[ -f "$SCHEDULE_FILE" ]]; then
  log "Aplicando Schedule de Respaldo recurrente (${SCHEDULE_FILE})..."
  kubectl apply -f "${SCHEDULE_FILE}"
fi

log_success "Velero v1.18.3 ha sido desplegado exitosamente en el cluster."
echo ""
velero version || true
echo ""
log "Schedules activos:"
velero schedule get || true
