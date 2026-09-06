# ==============================================================================
# HashiCorp Vault Local Initialization & Seeding Script (PowerShell for Windows)
# ==============================================================================
param (
    [string]$VaultAddr = "http://localhost:8200",
    [string]$VaultToken = "root"
)

Write-Host "🔐 [Vault Init] Connecting to Vault at $VaultAddr..." -ForegroundColor Cyan

# 1. Detect if Vault is running in Kubernetes or Docker
$vaultPod = (kubectl get pods -n vault -l app=vault -o jsonpath="{.items[0].metadata.name}" 2>$null)

function Invoke-VaultCommand {
    param([string[]]$VaultArgs)
    if ($vaultPod) {
        kubectl exec -n vault $vaultPod -- vault @VaultArgs
    } else {
        docker exec -e VAULT_ADDR="http://127.0.0.1:8200" -e VAULT_TOKEN="$VaultToken" vault vault @VaultArgs
    }
}

# 1. Enable KV v2 Secret Engine
Invoke-VaultCommand @("secrets", "enable", "-path=secret", "kv-v2") 2>$null
if ($LASTEXITCODE -eq 0) {
    Write-Host "✅ KV v2 secret engine enabled at 'secret/'" -ForegroundColor Green
} else {
    Write-Host "ℹ️ Secret engine 'secret/' already enabled." -ForegroundColor Yellow
}

# 2. Seed Secrets
Write-Host "📦 Seeding microservices secrets into Vault KV..." -ForegroundColor Cyan

Invoke-VaultCommand @("kv", "put", "secret/application", "spring.datasource.username=postgres", "spring.datasource.password=admin", "jwt.secret=super-secure-jwt-secret-key-for-microservices-dev-environment-12345")
Invoke-VaultCommand @("kv", "put", "secret/products-service", "spring.datasource.url=jdbc:postgresql://db-products:5432/ms_products", "spring.datasource.username=postgres", "spring.datasource.password=admin")
Invoke-VaultCommand @("kv", "put", "secret/orders-service", "spring.datasource.url=jdbc:postgresql://db-orders:5432/ms_orders", "spring.datasource.username=postgres", "spring.datasource.password=admin", "spring.kafka.bootstrap-servers=kafka:9092")
Invoke-VaultCommand @("kv", "put", "secret/inventory-service", "spring.datasource.url=jdbc:postgresql://db-inventory:5432/ms_inventory", "spring.datasource.username=postgres", "spring.datasource.password=admin")
Invoke-VaultCommand @("kv", "put", "secret/notification-service", "spring.kafka.bootstrap-servers=kafka:9092", "spring.mail.username=notification@microservices.local", "spring.mail.password=dev-mail-password")
Invoke-VaultCommand @("kv", "put", "secret/api-gateway", "keycloak.client-secret=microservices-client-secret-key-12345", "keycloak.issuer-uri=http://keycloak:8181/realms/microservices-realm")

Write-Host "🎉 [Vault Init] Secrets initialized successfully!" -ForegroundColor Green
Write-Host "👉 Vault UI available at: http://localhost:8200 (Token: $VaultToken)" -ForegroundColor White
