#!/usr/bin/env bash
# ==============================================================================
# 📦 Velero CLI v1.18.3 Production Installer
# ==============================================================================
# Usage:
#   ./scripts/install-velero.sh [v1.18.3]
#   VELERO_INSTALL_DIR=/usr/bin ./scripts/install-velero.sh
# ==============================================================================
set -Eeuo pipefail

velero_version="${1:-v1.18.3}"
if [[ ! "$velero_version" =~ ^v1\.[0-9]+\.[0-9]+$ ]]; then
  echo "❌ Error: Se esperaba una versión de Velero válida (ej: v1.18.3). Recibido: ${velero_version}" >&2
  exit 2
fi

install_dir="${VELERO_INSTALL_DIR:-/usr/local/bin}"

# Detección de OS
os="$(uname -s | tr '[:upper:]' '[:lower:]')"
case "$os" in
  linux*)  os="linux" ;;
  darwin*) os="darwin" ;;
  *)
    echo "❌ Error: Sistema operativo no soportado por este instalador: ${os}" >&2
    exit 1
    ;;
esac

# Detección de Arquitectura
arch="$(uname -m)"
case "$arch" in
  x86_64|amd64)  arch="amd64" ;;
  aarch64|arm64) arch="arm64" ;;
  *)
    echo "❌ Error: Arquitectura no soportada: ${arch}" >&2
    exit 1
    ;;
esac

archive_name="velero-${velero_version}-${os}-${arch}.tar.gz"
download_url="https://github.com/vmware-tanzu/velero/releases/download/${velero_version}/${archive_name}"

temp_dir="$(mktemp -d)"
cleanup() {
  rm -rf "$temp_dir"
}
trap cleanup EXIT ERR INT TERM

echo "⬇️  Descargando Velero CLI ${velero_version} (${os}-${arch})..."
echo "   URL: ${download_url}"

if command -v curl >/dev/null 2>&1; then
  curl --fail --silent --show-error --location "${download_url}" --output "${temp_dir}/${archive_name}"
elif command -v wget >/dev/null 2>&1; then
  wget --quiet --output-document="${temp_dir}/${archive_name}" "${download_url}"
else
  echo "❌ Error: Se requiere 'curl' o 'wget' para descargar Velero." >&2
  exit 1
fi

echo "📦 Descomprimiendo binario..."
tar -xzf "${temp_dir}/${archive_name}" -C "${temp_dir}"

extracted_binary="${temp_dir}/velero-${velero_version}-${os}-${arch}/velero"
if [[ ! -f "$extracted_binary" ]]; then
  echo "❌ Error: No se encontró el binario extraído en ${extracted_binary}" >&2
  exit 1
fi

chmod +x "$extracted_binary"

echo "🚀 Instalando en ${install_dir}/velero..."
if [[ -w "$install_dir" ]]; then
  mv "$extracted_binary" "${install_dir}/velero"
else
  if command -v sudo >/dev/null 2>&1; then
    sudo mv "$extracted_binary" "${install_dir}/velero"
  else
    echo "❌ Error: No hay permisos de escritura en ${install_dir} y 'sudo' no está disponible." >&2
    exit 1
  fi
fi

echo "✅ Velero CLI instalado con éxito:"
"${install_dir}/velero" version --client-only || true
