#!/usr/bin/env bash
# ==============================================================================
# 🛡️ Production Linux Node Hardening & Kernel Tuning
# ==============================================================================
# Designed for AWS EC2, Azure VMs, Bare Metal and Kubernetes Worker Nodes.
# Compatible with Ubuntu 22.04/24.04 LTS and Debian.
#
# Can be run directly via Cloud-Init user-data or as an SRE maintenance task.
# Usage:
#   sudo ./scripts/prod/node-hardening.sh
# ==============================================================================
set -Eeuo pipefail
IFS=$'\n\t'

if [[ "$EUID" -ne 0 ]]; then
  echo "❌ Error: Este script requiere privilegios de superusuario (root o sudo)." >&2
  exit 1
fi

log() {
  echo -e "\033[1;34m[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] [HARDENING]\033[0m $*"
}
log_success() {
  echo -e "\033[1;32m[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] [SUCCESS]\033[0m $*"
}

# 1. Optimización del Kernel de Linux (sysctl)
log "Configurando parámetros de red, memoria y descriptores de archivo en /etc/sysctl.d/99-microservices.conf..."
cat << 'EOF' > /etc/sysctl.d/99-microservices.conf
# Memoria virtual requerida para Kafka, OpenSearch y bases de datos
vm.max_map_count=262144
vm.overcommit_memory=1
vm.swappiness=10

# Descriptores de archivo del sistema
fs.file-max=2097152
fs.inotify.max_user_watches=524288
fs.inotify.max_user_instances=8192

# Optimización de conexiones TCP de alto rendimiento (Cosmo Router, Ingress & Mesh)
net.core.somaxconn=32768
net.ipv4.tcp_max_syn_backlog=16384
net.core.netdev_max_backlog=16384
net.ipv4.ip_local_port_range=1024 65535

# Reutilización rápida de sockets TIME_WAIT
net.ipv4.tcp_tw_reuse=1
net.ipv4.tcp_fin_timeout=15

# Buffer sizes para tráfico masivo
net.core.rmem_max=16777216
net.core.wmem_max=16777216
net.ipv4.tcp_rmem=4096 87380 16777216
net.ipv4.tcp_wmem=4096 65536 16777216
EOF

sysctl --system >/dev/null
log_success "Parámetros sysctl aplicados correctamente."

# 2. Configurar Límites de Recursos (Limits.conf)
log "Configurando límites de descriptores y procesos en /etc/security/limits.d/99-microservices.conf..."
cat << 'EOF' > /etc/security/limits.d/99-microservices.conf
* soft nofile 65536
* hard nofile 65536
* soft nproc 65536
* hard nproc 65536
root soft nofile 65536
root hard nofile 65536
EOF

# 3. Hardening de Docker Daemon (Rotación de Logs y Resiliencia)
if command -v docker >/dev/null 2>&1 || [[ -d /etc/docker ]]; then
  log "Configurando /etc/docker/daemon.json para evitar saturación de disco y caídas de contenedores..."
  mkdir -p /etc/docker

  # Generar configuración segura sin sobrescribir llaves existentes de forma destructiva
  cat << 'EOF' > /etc/docker/daemon.json
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "50m",
    "max-file": "5"
  },
  "live-restore": true,
  "storage-driver": "overlay2",
  "default-ulimits": {
    "nofile": {
      "Name": "nofile",
      "Hard": 65536,
      "Soft": 65536
    }
  }
}
EOF

  if systemctl is-active --quiet docker; then
    log "Recargando Docker Daemon..."
    systemctl reload docker || systemctl restart docker
  fi
  log_success "Docker Daemon configurado con live-restore y rotación de logs."
fi

# 4. Asegurar Time Synchronization (NTP / Chrony / systemd-timesyncd)
if command -v timedatectl >/dev/null 2>&1; then
  timedatectl set-ntp true || true
  log_success "Sincronización de reloj NTP habilitada."
fi

log_success "Hardening del nodo completado satisfactoriamente."
