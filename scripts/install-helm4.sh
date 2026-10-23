#!/usr/bin/env bash
set -euo pipefail

helm_version="${1:-v4.3.1}"
if [[ ! "$helm_version" =~ ^v4\.[0-9]+\.[0-9]+$ ]]; then
  echo "Expected a pinned Helm 4 version (for example v4.3.1); got: $helm_version" >&2
  exit 2
fi

install_dir="${HELM_INSTALL_DIR:-/usr/local/bin}"
temp_dir="$(mktemp -d)"
trap 'rm -rf "$temp_dir"' EXIT

curl --fail --silent --show-error --location \
  "https://raw.githubusercontent.com/helm/helm/${helm_version}/scripts/get-helm-4" \
  --output "$temp_dir/get-helm-4"
chmod 700 "$temp_dir/get-helm-4"
HELM_INSTALL_DIR="$install_dir" "$temp_dir/get-helm-4" --version "$helm_version"
command -v helm >/dev/null
helm version --short
