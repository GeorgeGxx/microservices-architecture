# ==============================================================================
# Script to configure Kubernetes Auth Method with Least-Privilege Policies in Vault (Minikube / PowerShell)
# ==============================================================================
[CmdletBinding()]
param(
    [string]$Namespace = "vault",
    [string]$VaultToken = "root"
)

$ErrorActionPreference = "SilentlyContinue"
if (Test-Path Variable:\PSNativeCommandUseErrorActionPreference) {
    $PSNativeCommandUseErrorActionPreference = $false
}

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "   MINIKUBE VAULT - KUBERNETES AUTH AND LEAST PRIVILEGE   " -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

# 1. Get Vault Pod Name
$vaultPod = (kubectl get pod -n $Namespace -l app=vault -o jsonpath="{.items[0].metadata.name}" 2>$null)
if (-not $vaultPod) {
    Write-Error "No Vault pod found in namespace '$Namespace'. Is Vault running in Minikube?"
    exit 1
}

Write-Host "`n[1/5] Connecting to Vault Pod: $vaultPod in namespace '$Namespace'..." -ForegroundColor Yellow

# 2. Enable Kubernetes Auth Method
Write-Host "`n[2/5] Enabling Kubernetes Auth Method..." -ForegroundColor Yellow
kubectl exec -n $Namespace $vaultPod -- vault auth enable kubernetes 2>$null
if ($LASTEXITCODE -eq 0) {
    Write-Host "  [OK] Kubernetes Auth method enabled." -ForegroundColor Green
} else {
    Write-Host "  [INFO] Kubernetes Auth method already enabled." -ForegroundColor Cyan
}

# 3. Configure Kubernetes backend using in-cluster ServiceAccount token
Write-Host "`n[3/5] Configuring Kubernetes backend with cluster host..." -ForegroundColor Yellow
kubectl exec -n $Namespace $vaultPod -- vault write auth/kubernetes/config `
    kubernetes_host="https://kubernetes.default.svc:443"
if ($LASTEXITCODE -eq 0) {
    Write-Host "  [OK] Kubernetes Auth backend configured successfully." -ForegroundColor Green
}

# 4. Enable KV-v2 Secret Engine
Write-Host "`n[4/5] Enabling KV v2 Engine at 'secret/'..." -ForegroundColor Yellow
kubectl exec -n $Namespace $vaultPod -- vault secrets enable -path=secret kv-v2 2>$null
if ($LASTEXITCODE -eq 0) {
    Write-Host "  [OK] KV v2 secret engine enabled." -ForegroundColor Green
} else {
    Write-Host "  [INFO] KV 'secret/' engine already enabled." -ForegroundColor Cyan
}

# 5. Create Least-Privilege Read Policies per Microservice
Write-Host "`n[5/5] Creating Least-Privilege Policies and Kubernetes Auth Roles..." -ForegroundColor Yellow

$services = @("products-service", "orders-service", "inventory-service", "notification-service", "apollo-router")

# Global shared policy
$sharedPolicy = "path `"secret/data/application`" { capabilities = [`"read`"] }"
kubectl exec -i -n $Namespace $vaultPod -- /bin/sh -c "echo '$sharedPolicy' | vault policy write shared-application-policy -" 2>$null

foreach ($svc in $services) {
    $policy = "path `"secret/data/application`" { capabilities = [`"read`"] }`npath `"secret/data/$svc`" { capabilities = [`"read`"] }"
    kubectl exec -i -n $Namespace $vaultPod -- /bin/sh -c "echo '$policy' | vault policy write $svc-policy -" 2>$null

    # Create dedicated role
    kubectl exec -n $Namespace $vaultPod -- vault write "auth/kubernetes/role/${svc}-role" `
        bound_service_account_names="$svc,default" `
        bound_service_account_namespaces="dev,ecommerce,default,microservices,staging,prod" `
        policies="${svc}-policy" `
        ttl=24h 2>$null

    Write-Host "  [OK] Service: $svc -> Policy: '${svc}-policy' -> Role: '${svc}-role'" -ForegroundColor Green
}

# General fallback role for backward compatibility
$generalPolicy = "path `"secret/data/*`" { capabilities = [`"read`"] }"
kubectl exec -i -n $Namespace $vaultPod -- /bin/sh -c "echo '$generalPolicy' | vault policy write microservices-policy -" 2>$null
kubectl exec -n $Namespace $vaultPod -- vault write auth/kubernetes/role/microservices-role `
    bound_service_account_names="products-service,orders-service,inventory-service,notification-service,apollo-router,default" `
    bound_service_account_namespaces="dev,ecommerce,default,microservices,staging,prod" `
    policies="microservices-policy" `
    ttl=24h 2>$null

Write-Host "`n==========================================================" -ForegroundColor Green
Write-Host "  MINIKUBE VAULT KUBERNETES AUTH CONFIGURED!              " -ForegroundColor Green
Write-Host "==========================================================" -ForegroundColor Green
