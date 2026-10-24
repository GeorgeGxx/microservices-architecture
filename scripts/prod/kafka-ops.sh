#!/usr/bin/env bash
# ==============================================================================
# 📨 Apache Kafka 8.3.2 (KRaft) Production Operations & Lag Monitor
# ==============================================================================
# Operational utility for inspecting topics, consumer groups, lag and DLQ queues.
# Works seamlessly with Docker Compose, Kubernetes Pods, or Linux Bastions.
#
# Usage:
#   ./scripts/prod/kafka-ops.sh list-topics
#   ./scripts/prod/kafka-ops.sh lag [--group <name>]
#   ./scripts/prod/kafka-ops.sh inspect-dlq [--limit 10]
#   ./scripts/prod/kafka-ops.sh reset-offset --group <name> --topic <name> [--dry-run|--execute]
# ==============================================================================
set -Eeuo pipefail
IFS=$'\n\t'

BOOTSTRAP_SERVER="${KAFKA_BOOTSTRAP_SERVER:-localhost:29092}"
CONTAINER_NAME="${KAFKA_CONTAINER:-kafka}"

log() {
  echo -e "\033[1;34m[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] [KAFKA-OPS]\033[0m $*"
}
log_success() {
  echo -e "\033[1;32m[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] [SUCCESS]\033[0m $*"
}
log_error() {
  echo -e "\033[1;31m[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] [ERROR]\033[0m $*" >&2
}

# Ejecutar comandos de Kafka dentro del contenedor o directamente si los binarios existen
exec_kafka() {
  local cmd="$1"
  shift
  if command -v "$cmd" >/dev/null 2>&1; then
    "$cmd" --bootstrap-server "${BOOTSTRAP_SERVER}" "$@"
  elif command -v docker >/dev/null 2>&1 && docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    docker exec "${CONTAINER_NAME}" "$cmd" --bootstrap-server "localhost:9092" "$@"
  elif command -v kubectl >/dev/null 2>&1; then
    local pod
    pod="$(kubectl get pods -n data -l app.kubernetes.io/name=kafka -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
    if [[ -n "$pod" ]]; then
      kubectl exec -n data "${pod}" -c kafka -- "$cmd" --bootstrap-server "localhost:9092" "$@"
    else
      log_error "No se pudo conectar a Kafka (ni CLI local, ni Docker, ni Pod de K8s encontrado)."
      exit 1
    fi
  else
    log_error "No se encontró el ejecutable de Kafka ni el contenedor '${CONTAINER_NAME}'."
    exit 1
  fi
}

COMMAND="${1:-help}"
shift || true

case "$COMMAND" in
  list-topics)
    log "Listando topics activos en Kafka (${BOOTSTRAP_SERVER})..."
    exec_kafka kafka-topics --list
    ;;

  lag)
    TARGET_GROUP="${1:-all}"
    if [[ "$TARGET_GROUP" == "--group" ]]; then
      TARGET_GROUP="$2"
    fi

    if [[ "$TARGET_GROUP" == "all" || -z "$TARGET_GROUP" ]]; then
      log "Obteniendo lista de grupos de consumidores..."
      GROUPS=$(exec_kafka kafka-consumer-groups --list)
      echo "$GROUPS" | while read -r group; do
        if [[ -n "$group" ]]; then
          echo -e "\n\033[1;36m📊 Consumer Group: ${group}\033[0m"
          exec_kafka kafka-consumer-groups --describe --group "$group" || true
        fi
      done
    else
      log "Describiendo lag para el grupo '${TARGET_GROUP}'..."
      exec_kafka kafka-consumer-groups --describe --group "${TARGET_GROUP}"
    fi
    ;;

  inspect-dlq)
    LIMIT="10"
    TOPIC="orders-topic-dlt"
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --limit) LIMIT="$2"; shift 2 ;;
        --topic) TOPIC="$2"; shift 2 ;;
        *) shift ;;
      esac
    done
    log "Inspeccionando los últimos ${LIMIT} mensajes en la Dead Letter Queue (${TOPIC})..."
    exec_kafka kafka-console-consumer --topic "${TOPIC}" --from-beginning --max-messages "${LIMIT}" --timeout-ms 5000 || true
    ;;

  reset-offset)
    GROUP=""
    TOPIC=""
    MODE="--dry-run"
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --group) GROUP="$2"; shift 2 ;;
        --topic) TOPIC="$2"; shift 2 ;;
        --execute) MODE="--execute"; shift ;;
        --dry-run) MODE="--dry-run"; shift ;;
        *) shift ;;
      esac
    done

    if [[ -z "$GROUP" || -z "$TOPIC" ]]; then
      log_error "Uso: $0 reset-offset --group <name> --topic <name> [--dry-run|--execute]"
      exit 1
    fi

    log "Ejecutando reseteo de offsets para Grupo: '${GROUP}' en Topic: '${TOPIC}' (Modo: ${MODE})..."
    exec_kafka kafka-consumer-groups --group "${GROUP}" --topic "${TOPIC}" --reset-offsets --to-earliest ${MODE}
    ;;

  help|--help|-h)
    echo "Uso: $0 {list-topics|lag|inspect-dlq|reset-offset} [opciones]"
    echo ""
    echo "Comandos:"
    echo "  list-topics                   Lista todos los topics configurados"
    echo "  lag [--group <nombre>]        Inspecciona el lag y particiones de consumidores"
    echo "  inspect-dlq [--limit N]       Inspecciona mensajes en la cola de errores (DLT)"
    echo "  reset-offset --group G --topic T [--dry-run|--execute]  Resetea offsets de forma controlada"
    exit 0
    ;;

  *)
    log_error "Comando desconocido: $COMMAND. Ejecuta '$0 help' para más detalles."
    exit 1
    ;;
esac
