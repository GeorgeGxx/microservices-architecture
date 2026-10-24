#!/usr/bin/env bash
# ==============================================================================
# 🩺 Enterprise SRE Production Health Audit & Triaje Toolkit
# ==============================================================================
# Zero-dependency Bash diagnostic tool for high-pressure production incident triage.
#
# Usage:
#   ./scripts/prod/sre-health-audit.sh [--env local|k8s|cloud]
#   ./scripts/prod/sre-health-audit.sh --dump-jvm <java-pid>
#   ./scripts/prod/sre-health-audit.sh --quick
# ==============================================================================
set -Eeuo pipefail
IFS=$'\n\t'

ENV_MODE="${1:-local}"

# --- Configuration Maps by Environment ---
if [[ "$ENV_MODE" == "k8s" ]]; then
  KEYCLOAK_URL="${KEYCLOAK_URL:-http://keycloak.auth.svc.cluster.local:8181}"
  COSMO_ROUTER_URL="${COSMO_ROUTER_URL:-http://cosmo-router.dev.svc.cluster.local:8080}"
  VAULT_URL="${VAULT_URL:-http://vault.vault.svc.cluster.local:8200}"
  PRODUCTS_URL="${PRODUCTS_URL:-http://products-service.dev.svc.cluster.local:8004}"
  ORDERS_URL="${ORDERS_URL:-http://orders-service.dev.svc.cluster.local:8003}"
  INVENTORY_URL="${INVENTORY_URL:-http://inventory-service.dev.svc.cluster.local:8001}"
  NOTIF_URL="${NOTIF_URL:-http://notification-service.dev.svc.cluster.local:8002}"
  MLFLOW_URL="${MLFLOW_URL:-http://mlflow.dev.svc.cluster.local:5000}"
  KAFKA_HOST="kafka.data.svc.cluster.local"
  KAFKA_PORT="9092"
  REDIS_HOST="redis.data.svc.cluster.local"
  REDIS_PORT="6379"
else
  KEYCLOAK_URL="${KEYCLOAK_URL:-http://localhost:8181}"
  COSMO_ROUTER_URL="${COSMO_ROUTER_URL:-http://localhost:8080}"
  VAULT_URL="${VAULT_URL:-http://localhost:8200}"
  PRODUCTS_URL="${PRODUCTS_URL:-http://localhost:8004}"
  ORDERS_URL="${ORDERS_URL:-http://localhost:8003}"
  INVENTORY_URL="${INVENTORY_URL:-http://localhost:8001}"
  NOTIF_URL="${NOTIF_URL:-http://localhost:8002}"
  MLFLOW_URL="${MLFLOW_URL:-http://localhost:5000}"
  KAFKA_HOST="localhost"
  KAFKA_PORT="29092"
  REDIS_HOST="localhost"
  REDIS_PORT="6379"
fi

FAILURES=0

log_header() {
  echo -e "\n\033[1;36m====================================================================\033[0m"
  echo -e "\033[1;36m  🔍 $*\033[0m"
  echo -e "\033[1;36m====================================================================\033[0m"
}

check_http() {
  local service_name="$1"
  local url="$2"
  local expected_code="${3:-200}"
  local timeout="${4:-3}"

  local start_time
  start_time="$(date +%s%N 2>/dev/null || date +%s)"
  local http_code
  http_code="$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout "${timeout}" --max-time "$((timeout + 2))" "$url" || echo "000")"

  if [[ "$http_code" == "$expected_code" ]]; then
    printf "  ✅ %-30s | HTTP %-3s | OK (%s)\n" "$service_name" "$http_code" "$url"
  else
    printf "  ❌ %-30s | HTTP %-3s | FAIL (Esperado %s en %s)\n" "$service_name" "$http_code" "$expected_code" "$url"
    FAILURES=$((FAILURES + 1))
  fi
}

check_socket() {
  local service_name="$1"
  local host="$2"
  local port="$3"

  if timeout 2 bash -c "</dev/tcp/${host}/${port}" 2>/dev/null; then
    printf "  ✅ %-30s | PORT %-5s | OK (${host}:${port})\n" "$service_name" "$port"
  else
    printf "  ❌ %-30s | PORT %-5s | FAIL (No responde en ${host}:${port})\n" "$service_name" "$port"
    FAILURES=$((FAILURES + 1))
  fi
}

dump_jvm_triage() {
  local pid="$1"
  log_header "TRIAGE DE EMERGENCIA: Volcado de Threads y Memoria JVM (PID: ${pid})"

  if ! command -v jcmd >/dev/null 2>&1; then
    echo "❌ Error: 'jcmd' (OpenJDK JDK) no está disponible en este host." >&2
    exit 1
  fi

  local dump_dir="artifacts/triage-$(date +%Y%m%d_%H%M%S)"
  mkdir -p "$dump_dir"

  echo "Capturando Thread Dump (Deadlocks / Stacktraces)..."
  jcmd "$pid" Thread.print > "${dump_dir}/threads.tdump"

  echo "Capturando resumen de Memoria Heap (Objetos más pesados)..."
  jcmd "$pid" GC.class_histogram > "${dump_dir}/class_histogram.txt"

  echo "Capturando banderas de VM y consumo de memoria nativa..."
  jcmd "$pid" VM.flags > "${dump_dir}/vm_flags.txt"
  jcmd "$pid" VM.native_memory summary > "${dump_dir}/native_memory.txt" 2>/dev/null || true

  echo "✅ Archivos de diagnóstico guardados en: ${dump_dir}"
  exit 0
}

# --- Dispatcher de subcomandos ---
if [[ "${1:-}" == "--dump-jvm" ]]; then
  if [[ -z "${2:-}" ]]; then
    echo "Uso: $0 --dump-jvm <PID>"
    exit 1
  fi
  dump_jvm_triage "$2"
fi

# --- Auditoría de Salud ---
log_header "MICROSERVICES ARCHITECTURE: AUDITORÍA DE SALUD EN PRODUCCIÓN (${ENV_MODE})"

echo "🌐 GATEWAY & FEDERATION LAYER:"
check_http "Cosmo Router GraphQL Health" "${COSMO_ROUTER_URL}/health/live" 200
check_http "Cosmo Router Readiness"     "${COSMO_ROUTER_URL}/health/ready" 200

echo ""
echo "⚙️ SPRING BOOT CORE DOMAIN SUBGRAPHS:"
check_http "Products Service Actuator"   "${PRODUCTS_URL}/actuator/health" 200
check_http "Orders Service Actuator"     "${ORDERS_URL}/actuator/health" 200
check_http "Inventory Service Actuator"  "${INVENTORY_URL}/actuator/health" 200
check_http "Notification Service Health" "${NOTIF_URL}/actuator/health" 200

echo ""
echo "🔐 SECURITY & IDENTITY PROVIDER:"
check_http "Keycloak OIDC Discovery"     "${KEYCLOAK_URL}/realms/microservices-realm/.well-known/openid-configuration" 200
check_http "HashiCorp Vault Seal Status" "${VAULT_URL}/v1/sys/seal-status" 200

echo ""
echo "🧪 MLOPS & EVENT BUS:"
check_http "MLflow Tracking Server"      "${MLFLOW_URL}/health" 200
check_socket "Apache Kafka KRaft Broker" "${KAFKA_HOST}" "${KAFKA_PORT}"
check_socket "Redis Cache & Rate Limit"  "${REDIS_HOST}" "${REDIS_PORT}"

echo ""
log_header "RESUMEN DEL ESTADO DE LA PLATAFORMA"
if [[ "$FAILURES" -eq 0 ]]; then
  echo -e "\033[1;32m✅ TODOS LOS COMPONENTES DE PRODUCCIÓN ESTÁN SALUDABLES Y OPERATIVOS.\033[0m\n"
  exit 0
else
  echo -e "\033[1;31m❌ SE DETECTARON ${FAILURES} COMPONENTES DEGRADADOS O CAÍDOS.\033[0m\n"
  exit 1
fi
