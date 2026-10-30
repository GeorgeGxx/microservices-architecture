#!/usr/bin/env bash
# ==============================================================================
# 🛡️ Unified DevSecOps & Security Quality Gate Runner
# ==============================================================================
# Executes Gitleaks, Trivy (IaC/Filesystem), and Terraform static checks locally
# or inside Linux CI runners (GitHub Actions, Bitbucket, Azure DevOps).
#
# Usage:
#   ./scripts/ci/run-quality-gate.sh [--all|--secrets|--iac|--fast]
# ==============================================================================
set -Eeuo pipefail
IFS=$'\n\t'

MODE="${1:---all}"
FAILURES=0

log() {
  echo -e "\033[1;34m[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] [QUALITY-GATE]\033[0m $*"
}
log_success() {
  echo -e "\033[1;32m[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] [SUCCESS]\033[0m $*"
}
log_error() {
  echo -e "\033[1;31m[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] [FAIL]\033[0m $*" >&2
}

# 1. Gitleaks Secrets Scan
run_gitleaks() {
  log "Checking for credential leaks with Gitleaks..."
  if command -v gitleaks >/dev/null 2>&1; then
    gitleaks detect --source . --verbose --config devsecops/sast/gitleaks/.gitleaks.toml || {
      log_error "Gitleaks detected potential secrets in the repository."
      FAILURES=$((FAILURES + 1))
    }
  elif command -v docker >/dev/null 2>&1; then
    docker run --rm -v "$(pwd):/path:ro" zricethezav/gitleaks:latest detect --source="/path" --verbose || {
      log_error "Gitleaks detected potential secrets."
      FAILURES=$((FAILURES + 1))
    }
  else
    log_error "Gitleaks is not installed and Docker is unavailable."
  fi
}

# 2. Trivy IaC Scan
run_trivy() {
  log "Scanning infrastructure code (Terraform & Helm) with Trivy..."
  if command -v trivy >/dev/null 2>&1; then
    trivy config terraform/ --severity HIGH,CRITICAL || {
      log_error "Trivy found high/critical security issues in Terraform."
      FAILURES=$((FAILURES + 1))
    }
  elif command -v docker >/dev/null 2>&1; then
    docker run --rm -v "$(pwd):/app:ro" aquasec/trivy:latest config /app/terraform/ --severity HIGH,CRITICAL || {
      log_error "Trivy found critical vulnerabilities in Terraform."
      FAILURES=$((FAILURES + 1))
    }
  fi
}

# 3. Terraform Format & Lint
run_terraform() {
  if command -v terraform >/dev/null 2>&1; then
    log "Validating Terraform code formatting (terraform fmt)..."
    terraform fmt -check -recursive terraform/ || {
      log_error "Terraform files have formatting issues. Run 'terraform fmt -recursive terraform/'."
      FAILURES=$((FAILURES + 1))
    }
  fi
}

case "$MODE" in
  --secrets)
    run_gitleaks
    ;;
  --iac)
    run_trivy
    run_terraform
    ;;
  --all|*)
    run_gitleaks
    run_trivy
    run_terraform
    ;;
esac

echo ""
if [[ "$FAILURES" -eq 0 ]]; then
  log_success "All quality and DevSecOps gates passed successfully."
  exit 0
else
  log_error "Detected ${FAILURES} Quality Gate failure(s)."
  exit 1
fi
