#!/usr/bin/env bash
# ==============================================================================
# Docker Hub 2-Version Release Retention Enforcer (Active + Rollback)
# ==============================================================================
# Retains exactly the approved release tags 1.0.0 and 1.1.0 per repository,
# plus their Cosign signature/attestation tags. All other tags are pruned.
# ==============================================================================
set -euo pipefail

OWNER="${1:-${DOCKERHUB_OWNER:-georgegxx}}"
REPO="${2:-${INPUT_SERVICE_NAME:-}}"
DRY_RUN="${DRY_RUN:-false}"
ALLOWED_RELEASE_TAGS=("1.0.0" "1.1.0")

DOCKER_USER="${DOCKERHUB_USERNAME:-${DOCKER_USERNAME:-$OWNER}}"
DOCKER_PASS="${DOCKERHUB_TOKEN:-${DOCKER_PASSWORD:-}}"

if [ -z "$REPO" ]; then
  echo "::error::Usage: $0 <owner> <repository>"
  exit 1
fi

if [ -z "$DOCKER_PASS" ]; then
  if [ "$DRY_RUN" != "true" ]; then
    echo "::error::Docker Hub credentials are required to enforce the release-tag retention policy for ${OWNER}/${REPO}."
    exit 1
  fi
fi

echo "── Docker Hub Retention Policy: ${OWNER}/${REPO} (Keep 1.0.0 and 1.1.0 only) ──"

HUB_TOKEN=""
if [ -n "$DOCKER_PASS" ]; then
  LOGIN_PAYLOAD="$(jq -n --arg u "$DOCKER_USER" --arg p "$DOCKER_PASS" '{username: $u, password: $p}')"
  HUB_TOKEN="$(curl -fsSL -X POST "https://hub.docker.com/v2/users/login/" \
    -H "Content-Type: application/json" \
    -d "$LOGIN_PAYLOAD" 2>/dev/null | jq -r '.token // empty' || true)"

  if [ -z "$HUB_TOKEN" ]; then
    echo "::error::Could not obtain Docker Hub API JWT token for ${OWNER}/${REPO}; refusing to skip retention cleanup."
    exit 1
  fi
fi

TAGS_JSON='{"results":[]}'
NEXT_URL="https://hub.docker.com/v2/repositories/${OWNER}/${REPO}/tags/?page_size=100"
while [ -n "$NEXT_URL" ]; do
  case "$NEXT_URL" in
    "https://hub.docker.com/v2/repositories/${OWNER}/${REPO}/tags/"*) ;;
    *) echo "::error::Unexpected Docker Hub pagination URL; aborting before pruning."; exit 1 ;;
  esac
  CURL_AUTH=()
  if [ -n "$HUB_TOKEN" ]; then CURL_AUTH=(-H "Authorization: JWT ${HUB_TOKEN}"); fi
  PAGE_JSON="$(curl -fsSL "${CURL_AUTH[@]}" "$NEXT_URL")" || {
    echo "::error::Failed to fetch all Docker Hub tags; aborting before pruning."
    exit 1
  }
  if [ "$(echo "$PAGE_JSON" | jq -r '.results | type // empty')" != "array" ]; then
    echo "::error::Docker Hub returned an invalid tag page; aborting before pruning."
    exit 1
  fi
  TAGS_JSON="$(jq -cn --argjson accumulated "$TAGS_JSON" --argjson page "$PAGE_JSON" \
    '{results: ($accumulated.results + $page.results)}')"
  NEXT_URL="$(echo "$PAGE_JSON" | jq -r '.next // empty')"
done

ALL_TAGS="$(echo "$TAGS_JSON" | jq -r '.results[].name')"
if [ -z "$ALL_TAGS" ]; then
  echo "  [INFO] No tags found in ${OWNER}/${REPO}."
  exit 0
fi

KEEP_RELEASE_TAGS=""
for allowed_tag in "${ALLOWED_RELEASE_TAGS[@]}"; do
  if echo "$ALL_TAGS" | grep -Fxq "$allowed_tag"; then
    KEEP_RELEASE_TAGS="${KEEP_RELEASE_TAGS}${allowed_tag}"$'\n'
  fi
done

# Collect digests for kept SemVer tags so their Cosign .sig/.att/.sbom artifacts are preserved
KEEP_COSIGN_PREFIXES=""
while IFS= read -r kept_tag; do
  [ -z "$kept_tag" ] && continue
  digest="$(echo "$TAGS_JSON" | jq -r --arg t "$kept_tag" '.results[] | select(.name == $t) | .digest // empty')"
  if [[ "$digest" =~ ^sha256:([0-9a-f]{64})$ ]]; then
    KEEP_COSIGN_PREFIXES="${KEEP_COSIGN_PREFIXES} sha256-${BASH_REMATCH[1]}"
  fi
done <<< "$KEEP_RELEASE_TAGS"

while IFS= read -r tag; do
  [ -z "$tag" ] && continue

  # 1. Preserve only the two explicitly approved release versions.
  if echo "$KEEP_RELEASE_TAGS" | grep -Fxq "$tag"; then
    echo "  [KEEP]   ${OWNER}/${REPO}:${tag} (Approved rollback release)"
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

  # 3. Prune every non-approved version or mutable/commit-SHA tag.
  if [ "$DRY_RUN" = "true" ]; then
    echo "  [WOULD PRUNE] ${OWNER}/${REPO}:${tag}"
    continue
  fi

  HTTP_STATUS="$(curl -sS -o /dev/null -w "%{http_code}" -X DELETE \
    -H "Authorization: JWT ${HUB_TOKEN}" \
    "https://hub.docker.com/v2/repositories/${OWNER}/${REPO}/tags/${tag}/" || echo "000")"

  if [ "$HTTP_STATUS" = "204" ] || [ "$HTTP_STATUS" = "200" ]; then
    echo "  [PRUNED] ${OWNER}/${REPO}:${tag} (Removed stale/non-release tag)"
  else
    echo "::error::Could not delete ${OWNER}/${REPO}:${tag} (HTTP ${HTTP_STATUS}); verify DOCKERHUB_TOKEN has Delete permissions."
    exit 1
  fi
done <<< "$ALL_TAGS"
