#!/usr/bin/env bash
# ==============================================================================
# Docker Hub 2-Version Release Retention Enforcer (Active + Rollback)
# ==============================================================================
# Retains at most MAX_VERSIONS (default: 2) immutable SemVer release tags per
# repository (e.g., 1.1.0 active + 1.0.0 rollback) along with their associated
# Cosign signature/attestation tags, and prunes all stale SemVer versions and
# mutable/commit-SHA tags via the Docker Hub v2 REST API.
# ==============================================================================
set -euo pipefail

OWNER="${1:-${DOCKERHUB_OWNER:-georgegxx}}"
REPO="${2:-${INPUT_SERVICE_NAME:-}}"
MAX_VERSIONS="${3:-2}"

DOCKER_USER="${DOCKERHUB_USERNAME:-${DOCKER_USERNAME:-$OWNER}}"
DOCKER_PASS="${DOCKERHUB_TOKEN:-${DOCKER_PASSWORD:-}}"

if [ -z "$REPO" ]; then
  echo "::error::Usage: $0 <owner> <repository> [max_semver_versions]"
  exit 1
fi

if [ -z "$DOCKER_PASS" ]; then
  echo "::notice::Docker Hub credentials not configured; skipping retention cleanup for ${OWNER}/${REPO}."
  exit 0
fi

echo "── Docker Hub Retention Policy: ${OWNER}/${REPO} (Keep top ${MAX_VERSIONS} SemVer releases) ──"

LOGIN_PAYLOAD="$(jq -n --arg u "$DOCKER_USER" --arg p "$DOCKER_PASS" '{username: $u, password: $p}')"
HUB_TOKEN="$(curl -fsSL -X POST "https://hub.docker.com/v2/users/login/" \
  -H "Content-Type: application/json" \
  -d "$LOGIN_PAYLOAD" 2>/dev/null | jq -r '.token // empty' || true)"

if [ -z "$HUB_TOKEN" ]; then
  echo "::warning::Could not obtain Docker Hub API JWT token for ${OWNER}/${REPO}; skipping tag pruning."
  exit 0
fi

TAGS_JSON="$(curl -fsSL -H "Authorization: JWT ${HUB_TOKEN}" \
  "https://hub.docker.com/v2/repositories/${OWNER}/${REPO}/tags/?page_size=100" 2>/dev/null || true)"

if [ -z "$TAGS_JSON" ] || [ "$(echo "$TAGS_JSON" | jq -r '.results | type // empty')" != "array" ]; then
  echo "  [INFO] Repository ${OWNER}/${REPO} has no existing tags or is not yet created."
  exit 0
fi

ALL_TAGS="$(echo "$TAGS_JSON" | jq -r '.results[].name')"
if [ -z "$ALL_TAGS" ]; then
  echo "  [INFO] No tags found in ${OWNER}/${REPO}."
  exit 0
fi

# Collect SemVer release tags (e.g., 1.0.0, 1.1.0) sorted highest version first
SEMVER_TAGS="$(echo "$ALL_TAGS" | grep -E '^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$' | sort -V -r || true)"

if [ -z "$SEMVER_TAGS" ]; then
  echo "  [INFO] No SemVer release tags found yet in ${OWNER}/${REPO}; skipping cleanup until a SemVer release is published."
  exit 0
fi

KEEP_SEMVER="$(echo "$SEMVER_TAGS" | head -n "$MAX_VERSIONS")"

# Collect digests for kept SemVer tags so their Cosign .sig/.att/.sbom artifacts are preserved
KEEP_COSIGN_PREFIXES=""
while IFS= read -r kept_tag; do
  [ -z "$kept_tag" ] && continue
  digest="$(echo "$TAGS_JSON" | jq -r --arg t "$kept_tag" '.results[] | select(.name == $t) | .digest // empty')"
  if [[ "$digest" =~ ^sha256:([0-9a-f]{64})$ ]]; then
    KEEP_COSIGN_PREFIXES="${KEEP_COSIGN_PREFIXES} sha256-${BASH_REMATCH[1]}"
  fi
done <<< "$KEEP_SEMVER"

while IFS= read -r tag; do
  [ -z "$tag" ] && continue

  # 1. Check if tag is in the top MAX_VERSIONS SemVer releases
  if echo "$KEEP_SEMVER" | grep -Fxq "$tag"; then
    echo "  [KEEP]   ${OWNER}/${REPO}:${tag} (Protected SemVer release)"
    continue
  fi

  # 2. Check if tag is a Cosign signature/attestation for a kept SemVer release
  keep_cosign=false
  for prefix in $KEEP_COSIGN_PREFIXES; do
    if [[ "$tag" == "${prefix}".* ]]; then
      keep_cosign=true
      break
    fi
  done
  if [ "$keep_cosign" = true ]; then
    echo "  [KEEP]   ${OWNER}/${REPO}:${tag} (Cosign artifact for active/rollback release)"
    continue
  fi

  # 3. Prune stale SemVer release or non-SemVer tag (e.g., commit SHA, buildcache)
  HTTP_STATUS="$(curl -sS -o /dev/null -w "%{http_code}" -X DELETE \
    -H "Authorization: JWT ${HUB_TOKEN}" \
    "https://hub.docker.com/v2/repositories/${OWNER}/${REPO}/tags/${tag}/" || echo "000")"

  if [ "$HTTP_STATUS" = "204" ] || [ "$HTTP_STATUS" = "200" ]; then
    echo "  [PRUNED] ${OWNER}/${REPO}:${tag} (Removed stale/non-release tag)"
  else
    echo "  [WARN]   Could not delete ${OWNER}/${REPO}:${tag} (HTTP ${HTTP_STATUS} — ensure DOCKERHUB_TOKEN has Delete permissions)"
  fi
done <<< "$ALL_TAGS"
