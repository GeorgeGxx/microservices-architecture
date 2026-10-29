#!/bin/sh
set -e

echo "🔐 [Vault Auto-Init] Waiting for Vault server..."
until vault status > /dev/null 2>&1; do
  sleep 1
done

echo "🛡️ [Vault Auto-Init] Enabling Audit Device logging..."
vault audit enable file file_path=/vault/file/vault_audit.log 2>/dev/null || true

echo "📦 [Vault Auto-Init] Enabling KV-v2 secret engine..."
vault secrets enable -path=secret kv-v2 2>/dev/null || true

echo "📦 [Vault Auto-Init] Seeding microservice secrets..."
vault kv put secret/application spring.datasource.username="postgres" spring.datasource.password="postgres" jwt.secret="super-secure-jwt-secret-key-3300" 2>/dev/null || true
vault kv put secret/products-service spring.datasource.username="postgres" spring.datasource.password="postgres" 2>/dev/null || true
vault kv put secret/orders-service spring.datasource.username="postgres" spring.datasource.password="postgres" 2>/dev/null || true
vault kv put secret/inventory-service spring.datasource.username="postgres" spring.datasource.password="postgres" 2>/dev/null || true
vault kv put secret/notification-service spring.mail.username="notification@microservices.local" spring.mail.password="dev-mail-password" 2>/dev/null || true
vault kv put secret/cosmo-router keycloak.client-secret="microservices-client-secret-key-3300" keycloak.issuer-uri="http://keycloak:8181/realms/microservices-realm" 2>/dev/null || true

echo "🔐 [Vault Auto-Init] Enabling Transit Encryption Engine..."
vault secrets enable transit 2>/dev/null || true
vault write -f transit/keys/microservices-data-key type=aes256-gcm96 2>/dev/null || true

echo "🗄️ [Vault Auto-Init] Enabling Dynamic Database Engine..."
vault secrets enable database 2>/dev/null || true

# Products Service Database
vault write database/config/postgres-products \
    plugin_name=postgresql-database-plugin \
    allowed_roles="products-db-role" \
    connection_url="postgresql://{{username}}:{{password}}@db-products:5432/ms_products?sslmode=disable" \
    username="${POSTGRES_USER}" \
    password="${POSTGRES_PASSWORD}" 2>/dev/null || true

vault write database/roles/products-db-role \
    db_name=postgres-products \
    creation_statements="CREATE ROLE \"{{name}}\" WITH LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}'; GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO \"{{name}}\";" \
    default_ttl="1h" \
    max_ttl="24h" 2>/dev/null || true

# Orders Service Database
vault write database/config/postgres-orders \
    plugin_name=postgresql-database-plugin \
    allowed_roles="orders-db-role" \
    connection_url="postgresql://{{username}}:{{password}}@db-orders:5432/ms_orders?sslmode=disable" \
    username="${POSTGRES_USER}" \
    password="${POSTGRES_PASSWORD}" 2>/dev/null || true

vault write database/roles/orders-db-role \
    db_name=postgres-orders \
    creation_statements="CREATE ROLE \"{{name}}\" WITH LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}'; GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO \"{{name}}\";" \
    default_ttl="1h" \
    max_ttl="24h" 2>/dev/null || true

# Inventory Service Database
vault write database/config/postgres-inventory \
    plugin_name=postgresql-database-plugin \
    allowed_roles="inventory-db-role" \
    connection_url="postgresql://{{username}}:{{password}}@db-inventory:5432/ms_inventory?sslmode=disable" \
    username="${POSTGRES_USER}" \
    password="${POSTGRES_PASSWORD}" 2>/dev/null || true

vault write database/roles/inventory-db-role \
    db_name=postgres-inventory \
    creation_statements="CREATE ROLE \"{{name}}\" WITH LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}'; GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO \"{{name}}\";" \
    default_ttl="1h" \
    max_ttl="24h" 2>/dev/null || true

echo "🛡️ [Vault Auto-Init] Creating Least-Privilege Policies..."
for svc in products-service orders-service inventory-service notification-service; do
  echo "path \"secret/data/application\" { capabilities = [\"read\"] } path \"secret/data/${svc}\" { capabilities = [\"read\"] }" | vault policy write "${svc}-policy" - 2>/dev/null || true
done

echo "✅ [Vault Auto-Init] Enterprise Vault capabilities initialized successfully!"
exit 0
