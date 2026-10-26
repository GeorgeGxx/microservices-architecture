#!/usr/bin/env bash
# =============================================================================
# install-yq.sh — Pinned, deterministic installer for yq v4 (Mike Farah)
# Standardized across GitHub Actions, Azure DevOps, and Bitbucket Pipelines.
# =============================================================================
set -euo pipefail

yq_version="${1:-v4.44.3}"
if [[ ! "$yq_version" =~ ^v4\.[0-9]+\.[0-9]+$ ]]; then
  echo "Expected a pinned yq v4 version (for example v4.44.3); got: $yq_version" >&2
  exit 2
fi

install_dir="${YQ_INSTALL_DIR:-/usr/local/bin}"
sudo_cmd=""
if [ "$(id -u)" -ne 0 ] && command -v sudo >/dev/null 2>&1; then
  sudo_cmd="sudo"
fi

arch="$(uname -m)"
case "$arch" in
  x86_64|amd64) binary_arch="amd64" ;;
  aarch64|arm64) binary_arch="arm64" ;;
  *) echo "Unsupported architecture for yq: $arch" >&2; exit 1 ;;
esac

target_bin="$install_dir/yq"
if command -v yq >/dev/null 2>&1 && yq --version 2>&1 | grep -q "${yq_version#v}"; then
  echo "yq $yq_version is already installed at $(command -v yq)."
  exit 0
fi

temp_file="$(mktemp)"
trap 'rm -f "$temp_file"' EXIT

echo "Downloading yq ${yq_version} (${binary_arch})..."
curl --fail --silent --show-error --location \
  "https://github.com/mikefarah/yq/releases/download/${yq_version}/yq_linux_${binary_arch}" \
  --output "$temp_file"

chmod 755 "$temp_file"
$sudo_cmd mkdir -p "$install_dir"
$sudo_cmd cp "$temp_file" "$target_bin"
$sudo_cmd chmod 755 "$target_bin"

command -v yq >/dev/null
echo "Successfully installed $(yq --version)"
