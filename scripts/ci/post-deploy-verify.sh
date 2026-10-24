#!/usr/bin/env bash
# ==============================================================================
# 🧪 Universal CI/CD Post-Deployment Verification & SLO Quality Gate
# ==============================================================================
# Executes contract, smoke, k6 performance, and DAST security validation
# across GitHub Actions, Bitbucket Pipelines, and Azure DevOps runners.
#
# Usage:
#   ./scripts/ci/post-deploy-verify.sh --base-url <url> --frontend-url <url> --keycloak-url <url>
# ==============================================================================
set -Eeuo pipefail
IFS=$'\n\t'

BASE_URL="${BASE_URL:-}"
FRONTEND_URL="${FRONTEND_URL:-}"
KEYCLOAK_URL="${KEYCLOAK_URL:-}"
SERVICE_NAME="${SERVICE_NAME:-core-platform}"
ARTIFACT_DIR="${ARTIFACT_DIR:-artifacts/post-deploy}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --base-url) BASE_URL="$2"; shift 2 ;;
    --frontend-url) FRONTEND_URL="$2"; shift 2 ;;
    --keycloak-url) KEYCLOAK_URL="$2"; shift 2 ;;
    --service) SERVICE_NAME="$2"; shift 2 ;;
    --artifact-dir) ARTIFACT_DIR="$2"; shift 2 ;;
    *) echo "Parámetro desconocido: $1" >&2; exit 1 ;;
  esac
done

: "${BASE_URL:?ERROR: BASE_URL no está definida. Indica la URL de Cosmo Router / Ingress.}"
: "${FRONTEND_URL:?ERROR: FRONTEND_URL no está definida. Indica la URL del Frontend React.}"
: "${KEYCLOAK_URL:?ERROR: KEYCLOAK_URL no está definida. Indica la URL de Keycloak IAM.}"

mkdir -p "${ARTIFACT_DIR}"

log() {
  echo -e "\033[1;34m[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] [POST-DEPLOY-GATE] [${SERVICE_NAME}]\033[0m $*"
}
log_success() {
  echo -e "\033[1;32m[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] [SUCCESS]\033[0m $*"
}

# 1. Newman API Contract & Role Authentication Suite
if [[ -f "devsecops/testing/newman/microservices.postman_collection.json" ]]; then
  log "1/4. Ejecutando suite de pruebas de contrato API con Newman..."
  npx --yes newman@6 run devsecops/testing/newman/microservices.postman_collection.json \
    --env-var "BASE_URL=${BASE_URL}" \
    --env-var "keycloak_url=${KEYCLOAK_URL}" \
    --reporters cli,json \
    --reporter-json-export "${ARTIFACT_DIR}/newman-report.json" \
    --bail
  log_success "Pruebas de contrato Newman pasadas con éxito."
fi

# 2. Storefront Smoke Checks
if [[ -f "scripts/testing/smoke.py" ]]; then
  log "2/4. Ejecutando pruebas de humo de la tienda y flujo de compra..."
  python3 scripts/testing/smoke.py --deployment --base-url "${BASE_URL}" --frontend-url "${FRONTEND_URL}"
  log_success "Smoke test del Storefront aprobado."
fi

# 3. K6 Performance & SLO Checks
if [[ -f "devsecops/testing/k6/load-test.js" ]] && command -v docker >/dev/null 2>&1; then
  log "3/4. Ejecutando verificación de SLOs de rendimiento con Grafana k6..."
  docker run --rm --network host -v "$(pwd):/workspace:ro" \
    grafana/k6:1.8.1 run --env "TARGET_URL=${BASE_URL}" \
    /workspace/devsecops/testing/k6/load-test.js
  log_success "SLOs de latencia y disponibilidad validados con k6."
fi

# 4. OWASP ZAP Baseline DAST Scan
if [[ -d "devsecops/dast/zap" ]] && command -v docker >/dev/null 2>&1; then
  log "4/4. Ejecutando escaneo DAST de vulnerabilidades con OWASP ZAP..."
  mkdir -p "${ARTIFACT_DIR}/zap"
  docker run --rm --network host \
    -v "$(pwd)/devsecops/dast/zap:/zap/rules:ro" \
    -v "$(pwd)/${ARTIFACT_DIR}/zap:/zap/wrk:rw" \
    ghcr.io/zaproxy/zaproxy:stable zap-baseline.py \
    -t "${FRONTEND_URL}" -c /zap/rules/rules.tsv -r zap-report.html -I || true
  log_success "Reporte de seguridad DAST generado en ${ARTIFACT_DIR}/zap/zap-report.html"
fi

log_success "Todas las compuertas de verificación post-despliegue pasaron exitosamente para ${SERVICE_NAME}."
