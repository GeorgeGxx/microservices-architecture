#!/bin/sh
set -eu

DB_USER="${POSTGRES_USER:-postgres}"
DB_PASS="${POSTGRES_PASSWORD:?Set POSTGRES_PASSWORD before initializing Vault}"
DB_SUFFIX="${DB_HOST_SUFFIX:-}"
JWT_SECRET="${JWT_SECRET:-}"
KEYCLOAK_CLIENT_SECRET="${KEYCLOAK_CLIENT_SECRET:-}"

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

echo "[Vault Auto-Init] Seeding configured application secrets..."
if [ -n "$JWT_SECRET" ]; then
  vault kv put secret/application \
    spring.datasource.username="$DB_USER" \
    spring.datasource.password="$DB_PASS" \
    jwt.secret="$JWT_SECRET"
else
  vault kv put secret/application \
    spring.datasource.username="$DB_USER" \
    spring.datasource.password="$DB_PASS"
  echo "[Vault Auto-Init] JWT_SECRET is unset; no placeholder JWT credential was written." >&2
fi

for db_svc in products orders inventory payments fulfillment analytics; do
  vault kv put "secret/${db_svc}-service" \
    spring.datasource.username="$DB_USER" \
    spring.datasource.password="$DB_PASS" \
    db.username="$DB_USER" \
    db.password="$DB_PASS"
done

if [ -n "$KEYCLOAK_CLIENT_SECRET" ]; then
  vault kv put secret/cosmo-router keycloak.client-secret="$KEYCLOAK_CLIENT_SECRET"
else
  echo "[Vault Auto-Init] KEYCLOAK_CLIENT_SECRET is unset; no placeholder client credential was written." >&2
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
for svc in products-service orders-service inventory-service notification-service payments-service fulfillment-service analytics-service; do
  printf 'path "secret/data/application" { capabilities = ["read"] }\npath "secret/data/%s" { capabilities = ["read"] }\n' "$svc" \
    | vault policy write "${svc}-policy" -
done

echo "[Vault Auto-Init] Vault engines, configured secrets, database roles, and policies are ready."
exit 0
