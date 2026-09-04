# ==============================================================================
# HashiCorp Vault Local Initialization & Seeding Script (PowerShell for Windows)
# ==============================================================================
param (
    [string]$VaultAddr = "http://localhost:8200",
    [string]$VaultToken = "root"
)

Write-Host "🔐 [Vault Init] Connecting to Vault at $VaultAddr..." -ForegroundColor Cyan

# 1. Enable KV v2 Secret Engine
docker exec -e VAULT_ADDR="http://127.0.0.1:8200" -e VAULT_TOKEN="$VaultToken" vault vault secrets enable -path=secret kv-v2 2>$null
if ($LASTEXITCODE -eq 0) {
    Write-Host "✅ KV v2 secret engine enabled at 'secret/'" -ForegroundColor Green
} else {
    Write-Host "ℹ️ Secret engine 'secret/' already enabled." -ForegroundColor Yellow
}

# 2. Seed Secrets
Write-Host "📦 Seeding microservices secrets into Vault KV..." -ForegroundColor Cyan

docker exec -e VAULT_ADDR="http://127.0.0.1:8200" -e VAULT_TOKEN="$VaultToken" vault vault kv put secret/application `
    spring.datasource.username="postgres" `
    spring.datasource.password="postgres" `
    jwt.secret="super-secure-jwt-secret-key-for-microservices-dev-environment-12345"

docker exec -e VAULT_ADDR="http://127.0.0.1:8200" -e VAULT_TOKEN="$VaultToken" vault vault kv put secret/products-service `
    spring.datasource.url="jdbc:postgresql://db-products:5432/ms_products" `
    spring.datasource.username="postgres" `
    spring.datasource.password="postgres"

docker exec -e VAULT_ADDR="http://127.0.0.1:8200" -e VAULT_TOKEN="$VaultToken" vault vault kv put secret/orders-service `
    spring.datasource.url="jdbc:postgresql://db-orders:5432/ms_orders" `
    spring.datasource.username="postgres" `
    spring.datasource.password="postgres" `
    spring.kafka.bootstrap-servers="kafka:9092"

docker exec -e VAULT_ADDR="http://127.0.0.1:8200" -e VAULT_TOKEN="$VaultToken" vault vault kv put secret/inventory-service `
    spring.datasource.url="jdbc:postgresql://db-inventory:5432/ms_inventory" `
    spring.datasource.username="postgres" `
    spring.datasource.password="postgres"

docker exec -e VAULT_ADDR="http://127.0.0.1:8200" -e VAULT_TOKEN="$VaultToken" vault vault kv put secret/notification-service `
    spring.kafka.bootstrap-servers="kafka:9092" `
    spring.mail.username="notification@microservices.local" `
    spring.mail.password="dev-mail-password"

docker exec -e VAULT_ADDR="http://127.0.0.1:8200" -e VAULT_TOKEN="$VaultToken" vault vault kv put secret/api-gateway `
    keycloak.client-secret="microservices-client-secret-key-12345" `
    keycloak.issuer-uri="http://keycloak:8181/realms/microservices-realm"

# 3. Create Least-Privilege Policies
Write-Host "🛡️ Configuring Least-Privilege Policies in Vault..." -ForegroundColor Cyan

$services = @("products-service", "orders-service", "inventory-service", "notification-service", "api-gateway")
foreach ($svc in $services) {
    $policy = "path `"secret/data/application`" { capabilities = [`"read`"] }`npath `"secret/data/$svc`" { capabilities = [`"read`"] }"
    docker exec -e VAULT_ADDR="http://127.0.0.1:8200" -e VAULT_TOKEN="$VaultToken" vault /bin/sh -c "echo '$policy' | vault policy write $svc-policy -" 2>$null
    Write-Host "  ✅ Policy '$svc-policy' configured." -ForegroundColor Green
}

Write-Host "🎉 [Vault Init] Secrets & Policies initialized successfully!" -ForegroundColor Green
Write-Host "👉 Vault UI available at: http://localhost:8200 (Token: $VaultToken)" -ForegroundColor White
