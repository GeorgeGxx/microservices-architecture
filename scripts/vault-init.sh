#!/bin/sh
set -eu

DB_USER="${POSTGRES_USER:-postgres}"
DB_PASS="${POSTGRES_PASSWORD:?Set POSTGRES_PASSWORD before initializing Vault}"
DB_SUFFIX="${DB_HOST_SUFFIX:-}"
REDIS_PASS="${REDIS_PASSWORD:-}"
JWT_SECRET="${JWT_SECRET:-}"
KEYCLOAK_CLIENT_ID="${KEYCLOAK_CLIENT_ID:-microservices_client}"
KEYCLOAK_CLIENT_SECRET="${KEYCLOAK_CLIENT_SECRET:-}"
KEYCLOAK_ADMIN_USER="${KEYCLOAK_ADMIN:-admin}"
KEYCLOAK_ADMIN_PASS="${KEYCLOAK_ADMIN_PASSWORD:-}"
KEYCLOAK_ISSUER="${KEYCLOAK_ISSUER_URI:-http://keycloak:8181/realms/microservices-realm}"
KEYCLOAK_JWK_URI="${KEYCLOAK_JWT_URI:-http://keycloak:8181/realms/microservices-realm/protocol/openid-connect/certs}"
GRAFANA_PASS="${GF_SECURITY_ADMIN_PASSWORD:-}"
GLITCHTIP_KEY="${GLITCHTIP_SECRET_KEY:-}"
GLITCHTIP_DB_PASS="${GLITCHTIP_DB_PASSWORD:-}"
GLITCHTIP_ADMIN_PASS="${GLITCHTIP_ADMIN_PASSWORD:-}"

echo "[Vault Auto-Init] Waiting for Vault server..."
until vault status >/dev/null 2>&1; do
  sleep 1
done

ensure_secret_mount() {
  mount_path="$1"
  mount_type="$2"
  if ! vault secrets list -format=json | grep -Fq "\"${mount_path}/\""; then
    vault secrets enable -path="$mount_path" "$mount_type"
  fi
}

echo "[Vault Auto-Init] Enabling audit logging if it is not already configured..."
if ! vault audit list -format=json | grep -Fq '"file/"'; then
  vault audit enable file file_path=/vault/file/vault_audit.log
fi

echo "[Vault Auto-Init] Ensuring KV-v2, Transit, and Database secret engines..."
ensure_secret_mount secret kv-v2
ensure_secret_mount transit transit
ensure_secret_mount database database

if ! vault read transit/keys/microservices-data-key >/dev/null 2>&1; then
  vault write -f transit/keys/microservices-data-key type=aes256-gcm96
fi

echo "[Vault Auto-Init] Seeding shared application, Keycloak, and cache secrets..."
vault kv put secret/application \
  spring.datasource.username="$DB_USER" \
  spring.datasource.password="$DB_PASS" \
  keycloak.client-id="$KEYCLOAK_CLIENT_ID" \
  keycloak.issuer-uri="$KEYCLOAK_ISSUER" \
  keycloak.jwk-set-uri="$KEYCLOAK_JWK_URI"

if [ -n "$REDIS_PASS" ]; then
  vault kv patch secret/application \
    spring.data.redis.password="$REDIS_PASS" \
    redis.password="$REDIS_PASS"
fi

if [ -n "$JWT_SECRET" ]; then
  vault kv patch secret/application jwt.secret="$JWT_SECRET"
else
  echo "[Vault Auto-Init] JWT_SECRET is unset; skipping jwt.secret." >&2
fi

if [ -n "$KEYCLOAK_CLIENT_SECRET" ]; then
  vault kv patch secret/application keycloak.client-secret="$KEYCLOAK_CLIENT_SECRET"
else
  echo "[Vault Auto-Init] KEYCLOAK_CLIENT_SECRET is unset; skipping keycloak.client-secret." >&2
fi

echo "[Vault Auto-Init] Seeding per-microservice database and OAuth2 client secrets..."
for db_svc in products orders inventory payments fulfillment analytics; do
  vault kv put "secret/${db_svc}-service" \
    spring.datasource.username="$DB_USER" \
    spring.datasource.password="$DB_PASS" \
    db.username="$DB_USER" \
    db.password="$DB_PASS" \
    keycloak.client-id="$KEYCLOAK_CLIENT_ID"
  if [ -n "$REDIS_PASS" ]; then
    vault kv patch "secret/${db_svc}-service" redis.password="$REDIS_PASS"
  fi
  if [ -n "$KEYCLOAK_CLIENT_SECRET" ]; then
    vault kv patch "secret/${db_svc}-service" keycloak.client-secret="$KEYCLOAK_CLIENT_SECRET"
  fi
done

for stateless_svc in notification-service ai-service demand-forecast; do
  vault kv put "secret/${stateless_svc}" keycloak.client-id="$KEYCLOAK_CLIENT_ID"
  if [ -n "$REDIS_PASS" ]; then
    vault kv patch "secret/${stateless_svc}" redis.password="$REDIS_PASS"
  fi
  if [ -n "$KEYCLOAK_CLIENT_SECRET" ]; then
    vault kv patch "secret/${stateless_svc}" keycloak.client-secret="$KEYCLOAK_CLIENT_SECRET"
  fi
done

vault kv put secret/cosmo-router \
  keycloak.client-id="$KEYCLOAK_CLIENT_ID" \
  keycloak.issuer-uri="$KEYCLOAK_ISSUER" \
  keycloak.jwk-set-uri="$KEYCLOAK_JWK_URI"
if [ -n "$KEYCLOAK_CLIENT_SECRET" ]; then
  vault kv patch secret/cosmo-router keycloak.client-secret="$KEYCLOAK_CLIENT_SECRET"
fi

echo "[Vault Auto-Init] Seeding Keycloak & Observability administrative secrets..."
vault kv put secret/keycloak \
  admin.username="$KEYCLOAK_ADMIN_USER" \
  client.id="$KEYCLOAK_CLIENT_ID" \
  db.username="$DB_USER" \
  db.password="$DB_PASS"
if [ -n "$KEYCLOAK_ADMIN_PASS" ]; then
  vault kv patch secret/keycloak admin.password="$KEYCLOAK_ADMIN_PASS"
fi
if [ -n "$KEYCLOAK_CLIENT_SECRET" ]; then
  vault kv patch secret/keycloak client.secret="$KEYCLOAK_CLIENT_SECRET"
fi

if [ -n "$GRAFANA_PASS" ] || [ -n "$GLITCHTIP_KEY" ] || [ -n "$GLITCHTIP_DB_PASS" ] || [ -n "$GLITCHTIP_ADMIN_PASS" ]; then
  vault kv put secret/observability initialized="true"
  [ -n "$GRAFANA_PASS" ] && vault kv patch secret/observability grafana.admin-password="$GRAFANA_PASS"
  [ -n "$GLITCHTIP_KEY" ] && vault kv patch secret/observability glitchtip.secret-key="$GLITCHTIP_KEY"
  [ -n "$GLITCHTIP_DB_PASS" ] && vault kv patch secret/observability glitchtip.db-password="$GLITCHTIP_DB_PASS"
  [ -n "$GLITCHTIP_ADMIN_PASS" ] && vault kv patch secret/observability glitchtip.admin-password="$GLITCHTIP_ADMIN_PASS"
fi

echo "[Vault Auto-Init] Configuring PostgreSQL dynamic database roles..."
for db_svc in products orders inventory payments fulfillment analytics; do
  vault write "database/config/postgres-${db_svc}" \
    plugin_name="postgresql-database-plugin" \
    verify_connection=false \
    allowed_roles="${db_svc}-db-role" \
    connection_url="postgresql://{{username}}:{{password}}@db-${db_svc}${DB_SUFFIX}:5432/ms_${db_svc}?sslmode=disable" \
    username="$DB_USER" \
    password="$DB_PASS"

  vault write "database/roles/${db_svc}-db-role" \
    db_name="postgres-${db_svc}" \
    creation_statements="CREATE ROLE \"{{name}}\" WITH LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}'; GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO \"{{name}}\";" \
    default_ttl="1h" \
    max_ttl="24h"
done

echo "[Vault Auto-Init] Writing least-privilege service policies..."
for svc in products-service orders-service inventory-service notification-service payments-service fulfillment-service analytics-service ai-service demand-forecast cosmo-router; do
  printf 'path "secret/data/application" { capabilities = ["read"] }\npath "secret/data/%s" { capabilities = ["read"] }\n' "$svc" \
    | vault policy write "${svc}-policy" -
done

printf 'path "secret/data/keycloak" { capabilities = ["read"] }\n' | vault policy write keycloak-policy -
printf 'path "secret/data/observability" { capabilities = ["read"] }\n' | vault policy write observability-policy -

echo "[Vault Auto-Init] Vault engines, configured secrets, database roles, and policies are ready."
exit 0
