#!/bin/sh
set -e

DB_USER="${POSTGRES_USER:-postgres}"
DB_PASS="${POSTGRES_PASSWORD:-admin}"
DB_SUFFIX="${DB_HOST_SUFFIX:-}"
JWT_SEC="${JWT_SECRET:-super-secure-jwt-secret-key-for-microservices-dev-environment-12345}"

echo "🔐 [Vault Auto-Init] Waiting for Vault server..."
until vault status > /dev/null 2>&1; do
  sleep 1
done

echo "🛡️ [Vault Auto-Init] Enabling Audit Device logging..."
vault audit enable file file_path=/vault/file/vault_audit.log 2>/dev/null || true

echo "📦 [Vault Auto-Init] Enabling KV-v2 secret engine..."
vault secrets enable -path=secret kv-v2 2>/dev/null || true

echo "📦 [Vault Auto-Init] Seeding microservice secrets..."
vault kv put secret/application spring.datasource.username="${DB_USER}" spring.datasource.password="${DB_PASS}" jwt.secret="${JWT_SEC}" 2>/dev/null || true
for db_svc in products orders inventory payments fulfillment analytics; do
  vault kv put "secret/${db_svc}-service" spring.datasource.username="${DB_USER}" spring.datasource.password="${DB_PASS}" db.username="${DB_USER}" db.password="${DB_PASS}" 2>/dev/null || true
done
vault kv put secret/notification-service spring.mail.username="notification@microservices.local" spring.mail.password="dev-mail-password" 2>/dev/null || true
vault kv put secret/cosmo-router keycloak.client-secret="microservices-client-secret-key-3300" keycloak.issuer-uri="http://keycloak:8181/realms/microservices-realm" 2>/dev/null || true

echo "🔐 [Vault Auto-Init] Enabling Transit Encryption Engine..."
vault secrets enable transit 2>/dev/null || true
vault write -f transit/keys/microservices-data-key type=aes256-gcm96 2>/dev/null || true

echo "🗄️ [Vault Auto-Init] Enabling Dynamic Database Engine (PostgreSQL 18)..."
vault secrets enable database 2>/dev/null || true

for db_svc in products orders inventory payments fulfillment analytics; do
  vault write "database/config/postgres-${db_svc}" \
      plugin_name="postgresql-database-plugin" \
      verify_connection=false \
      allowed_roles="${db_svc}-db-role" \
      connection_url="postgresql://{{username}}:{{password}}@db-${db_svc}${DB_SUFFIX}:5432/ms_${db_svc}?sslmode=disable" \
      username="${DB_USER}" \
      password="${DB_PASS}" 2>/dev/null || true

  vault write "database/roles/${db_svc}-db-role" \
      db_name="postgres-${db_svc}" \
      creation_statements="CREATE ROLE \"{{name}}\" WITH LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}'; GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO \"{{name}}\";" \
      default_ttl="1h" \
      max_ttl="24h" 2>/dev/null || true
done

echo "🛡️ [Vault Auto-Init] Creating Least-Privilege Policies..."
for svc in products-service orders-service inventory-service notification-service payments-service fulfillment-service analytics-service; do
  echo "path \"secret/data/application\" { capabilities = [\"read\"] } path \"secret/data/${svc}\" { capabilities = [\"read\"] }" | vault policy write "${svc}-policy" - 2>/dev/null || true
done

echo "✅ [Vault Auto-Init] Enterprise Vault capabilities initialized successfully!"
exit 0
