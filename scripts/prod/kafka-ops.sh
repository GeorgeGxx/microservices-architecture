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

BOOTSTRAP_SERVER="${KAFKA_BOOTSTRAP_SERVER:-localhost:29092}"
CONTAINER_NAME="${KAFKA_CONTAINER:-kafka}"

log() {
  echo -e "\033[1;34m[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] [KAFKA-OPS]\033[0m $*"
}
log_error() {
  echo -e "\033[1;31m[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] [ERROR]\033[0m $*" >&2
}

# Execute Kafka commands inside the container or directly if local binaries exist
exec_kafka() {
  local cmd="$1"
  shift
  if command -v "$cmd" >/dev/null 2>&1; then
    "$cmd" --bootstrap-server "${BOOTSTRAP_SERVER}" "$@"
  elif command -v docker >/dev/null 2>&1 && docker ps --format '{{.Names}}' | grep -Fxq -- "$CONTAINER_NAME"; then
    docker exec "${CONTAINER_NAME}" "$cmd" --bootstrap-server "localhost:9092" "$@"
  elif command -v kubectl >/dev/null 2>&1; then
    local pod
    pod="$(kubectl get pods -n data -l app.kubernetes.io/name=kafka --field-selector=status.phase=Running -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
    if [[ -n "$pod" ]]; then
      kubectl exec -n data "${pod}" -c kafka -- "$cmd" --bootstrap-server "localhost:9092" "$@"
    else
      log_error "Could not connect to Kafka (no local CLI, Docker container, or K8s Pod found)."
      exit 1
    fi
  else
    log_error "Neither Kafka binary nor container '${CONTAINER_NAME}' was found."
    exit 1
  fi
}

COMMAND="${1:-help}"
shift || true

case "$COMMAND" in
  list-topics)
    log "Listing active Kafka topics (${BOOTSTRAP_SERVER})..."
    exec_kafka kafka-topics --list
    ;;

  lag)
    TARGET_GROUP="${1:-all}"
    if [[ "$TARGET_GROUP" == "--group" ]]; then
      if [[ $# -lt 2 || -z "$2" ]]; then
        log_error "Usage: $0 lag [--group <name>]"
        exit 1
      fi
      TARGET_GROUP="$2"
    fi

    if [[ "$TARGET_GROUP" == "all" || -z "$TARGET_GROUP" ]]; then
      log "Retrieving consumer group list..."
      GROUPS=$(exec_kafka kafka-consumer-groups --list)
      echo "$GROUPS" | while read -r group; do
        if [[ -n "$group" ]]; then
          echo -e "\n\033[1;36m📊 Consumer Group: ${group}\033[0m"
          exec_kafka kafka-consumer-groups --describe --group "$group"
        fi
      done
    else
      log "Describing lag for group '${TARGET_GROUP}'..."
      exec_kafka kafka-consumer-groups --describe --group "${TARGET_GROUP}"
    fi
    ;;

  inspect-dlq)
    LIMIT="10"
    TOPIC="orders-topic.DLT"
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --limit) [[ $# -ge 2 ]] || { log_error "--limit requires a value"; exit 1; }; LIMIT="$2"; shift 2 ;;
        --topic) [[ $# -ge 2 ]] || { log_error "--topic requires a value"; exit 1; }; TOPIC="$2"; shift 2 ;;
        *) log_error "Unknown inspect-dlq option: $1"; exit 1 ;;
      esac
    done
    [[ "$LIMIT" =~ ^[1-9][0-9]*$ ]] || { log_error "--limit must be a positive integer"; exit 1; }
    log "Inspecting the last ${LIMIT} messages in the Dead Letter Queue (${TOPIC})..."
    exec_kafka kafka-console-consumer --topic "${TOPIC}" --from-beginning --max-messages "${LIMIT}" --timeout-ms 5000
    ;;

  replay-dlq)
    DLT_TOPIC="orders-topic.DLT"
    TARGET_TOPIC="orders-topic"
    LIMIT="10"
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --from) [[ $# -ge 2 ]] || { log_error "--from requires a topic"; exit 1; }; DLT_TOPIC="$2"; shift 2 ;;
        --to) [[ $# -ge 2 ]] || { log_error "--to requires a topic"; exit 1; }; TARGET_TOPIC="$2"; shift 2 ;;
        --limit) [[ $# -ge 2 ]] || { log_error "--limit requires a value"; exit 1; }; LIMIT="$2"; shift 2 ;;
        *) log_error "Unknown replay-dlq option: $1"; exit 1 ;;
      esac
    done
    [[ "$LIMIT" =~ ^[1-9][0-9]*$ ]] || { log_error "--limit must be a positive integer"; exit 1; }
    log_error "Console-based replay is disabled: it drops Kafka keys and headers. Use a header-preserving replay tool before retrying these records."
    exit 2
    ;;

  reset-offset)
    GROUP=""
    TOPIC=""
    MODE="--dry-run"
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --group) [[ $# -ge 2 ]] || { log_error "--group requires a value"; exit 1; }; GROUP="$2"; shift 2 ;;
        --topic) [[ $# -ge 2 ]] || { log_error "--topic requires a value"; exit 1; }; TOPIC="$2"; shift 2 ;;
        --execute) MODE="--execute"; shift ;;
        --dry-run) MODE="--dry-run"; shift ;;
        *) log_error "Unknown reset-offset option: $1"; exit 1 ;;
      esac
    done

    if [[ -z "$GROUP" || -z "$TOPIC" ]]; then
      log_error "Usage: $0 reset-offset --group <name> --topic <name> [--dry-run|--execute]"
      exit 1
    fi

    log "Executing offset reset for Group: '${GROUP}' on Topic: '${TOPIC}' (Mode: ${MODE})..."
    exec_kafka kafka-consumer-groups --group "${GROUP}" --topic "${TOPIC}" --reset-offsets --to-earliest "${MODE}"
    ;;

  help|--help|-h)
    echo "Usage: $0 {list-topics|lag|inspect-dlq|replay-dlq|reset-offset} [options]"
    echo ""
    echo "Commands:"
    echo "  list-topics                   List all configured topics"
    echo "  lag [--group <name>]          Inspect consumer group lag and partitions"
    echo "  inspect-dlq [--limit N]       Inspect messages in the Dead Letter Topic (DLT)"
    echo "  replay-dlq [--from DLT] [--to TOPIC] [--limit N]  Refuse unsafe replay that would drop Kafka keys/headers"
    echo "  reset-offset --group G --topic T [--dry-run|--execute]  Controlled consumer offset reset"
    exit 0
    ;;

  *)
    log_error "Unknown command: $COMMAND. Run '$0 help' for details."
    exit 1
    ;;
esac
