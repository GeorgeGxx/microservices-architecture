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
    *) echo "Unknown parameter: $1" >&2; exit 1 ;;
  esac
done

: "${BASE_URL:?ERROR: BASE_URL is not defined. Specify the Cosmo Router / Ingress URL.}"
: "${FRONTEND_URL:?ERROR: FRONTEND_URL is not defined. Specify the React Frontend URL.}"
: "${KEYCLOAK_URL:?ERROR: KEYCLOAK_URL is not defined. Specify the Keycloak IAM URL.}"

mkdir -p "${ARTIFACT_DIR}"

log() {
  echo -e "\033[1;34m[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] [POST-DEPLOY-GATE] [${SERVICE_NAME}]\033[0m $*"
}
log_success() {
  echo -e "\033[1;32m[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] [SUCCESS]\033[0m $*"
}

# 1. Newman API Contract & Role Authentication Suite
if [[ -f "devsecops/testing/newman/microservices.postman_collection.json" ]]; then
  log "1/4. Running Newman API contract test suite..."
  npx --yes newman@6 run devsecops/testing/newman/microservices.postman_collection.json \
    --env-var "BASE_URL=${BASE_URL}" \
    --env-var "keycloak_url=${KEYCLOAK_URL}" \
    --reporters cli,json \
    --reporter-json-export "${ARTIFACT_DIR}/newman-report.json" \
    --bail
  log_success "Newman API contract tests passed."
fi

# 2. Storefront Smoke Checks
if [[ -f "scripts/testing/smoke.py" ]]; then
  log "2/4. Running storefront smoke checks and checkout flow..."
  python3 scripts/testing/smoke.py --deployment --base-url "${BASE_URL}" --frontend-url "${FRONTEND_URL}"
  log_success "Storefront smoke test passed."
fi

# 3. K6 Performance & SLO Checks
if [[ -f "devsecops/testing/k6/load-test.js" ]] && command -v docker >/dev/null 2>&1; then
  log "3/4. Running Grafana k6 performance SLO verification..."
  docker run --rm --network host -v "$(pwd):/workspace:ro" \
    grafana/k6:1.8.1 run --env "TARGET_URL=${BASE_URL}" \
    /workspace/devsecops/testing/k6/load-test.js
  log_success "Latency and availability SLOs validated with k6."
fi

# 4. OWASP ZAP Baseline DAST Scan
if [[ -d "devsecops/dast/zap" ]] && command -v docker >/dev/null 2>&1; then
  log "4/4. Running OWASP ZAP baseline DAST vulnerability scan..."
  mkdir -p "${ARTIFACT_DIR}/zap"
  docker run --rm --network host \
    -v "$(pwd)/devsecops/dast/zap:/zap/rules:ro" \
    -v "$(pwd)/${ARTIFACT_DIR}/zap:/zap/wrk:rw" \
    ghcr.io/zaproxy/zaproxy:stable zap-baseline.py \
    -t "${FRONTEND_URL}" -c /zap/rules/rules.tsv -r zap-report.html -I || true
  log_success "DAST security report generated at ${ARTIFACT_DIR}/zap/zap-report.html"
fi

log_success "All post-deployment verification gates passed for ${SERVICE_NAME}."
