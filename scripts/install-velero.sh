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
  echo "❌ Error: Expected a valid Velero version (e.g., v1.18.3). Received: ${velero_version}" >&2
  exit 2
fi

install_dir="${VELERO_INSTALL_DIR:-/usr/local/bin}"

# OS Detection
os="$(uname -s | tr '[:upper:]' '[:lower:]')"
case "$os" in
  linux*)  os="linux" ;;
  darwin*) os="darwin" ;;
  *)
    echo "❌ Error: Operating system not supported by this installer: ${os}" >&2
    exit 1
    ;;
esac

# Architecture Detection
arch="$(uname -m)"
case "$arch" in
  x86_64|amd64)  arch="amd64" ;;
  aarch64|arm64) arch="arm64" ;;
  *)
    echo "❌ Error: Unsupported architecture: ${arch}" >&2
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

echo "⬇️  Downloading Velero CLI ${velero_version} (${os}-${arch})..."
echo "   URL: ${download_url}"

if command -v curl >/dev/null 2>&1; then
  curl --fail --silent --show-error --location "${download_url}" --output "${temp_dir}/${archive_name}"
elif command -v wget >/dev/null 2>&1; then
  wget --quiet --output-document="${temp_dir}/${archive_name}" "${download_url}"
else
  echo "❌ Error: Either 'curl' or 'wget' is required to download Velero." >&2
  exit 1
fi

echo "📦 Extracting binary..."
tar -xzf "${temp_dir}/${archive_name}" -C "${temp_dir}"

extracted_binary="${temp_dir}/velero-${velero_version}-${os}-${arch}/velero"
if [[ ! -f "$extracted_binary" ]]; then
  echo "❌ Error: Extracted binary not found at ${extracted_binary}" >&2
  exit 1
fi

chmod +x "$extracted_binary"

echo "🚀 Installing to ${install_dir}/velero..."
if [[ -w "$install_dir" ]]; then
  mv "$extracted_binary" "${install_dir}/velero"
else
  if command -v sudo >/dev/null 2>&1; then
    sudo mv "$extracted_binary" "${install_dir}/velero"
  else
    echo "❌ Error: No write permissions for ${install_dir} and 'sudo' is unavailable." >&2
    exit 1
  fi
fi

echo "✅ Velero CLI installed successfully:"
"${install_dir}/velero" version --client-only || true
