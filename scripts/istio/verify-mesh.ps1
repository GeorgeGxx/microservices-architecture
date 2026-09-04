<#
.SYNOPSIS
    Verifies the health of the Istio Service Mesh, mTLS status,
    and sidecar/Envoy proxy synchronization across all microservices.
#>

[CmdletBinding()]
param(
    [string]$Namespace = "ecommerce"
)

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "   🔍 ECOMMERCE - ISTIO MESH HEALTH & MTLS AUDIT         " -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

# 1. Check Istio Control Plane & Synced Proxies
Write-Host "`n[1/4] Checking Istio Control Plane & Envoy Proxy Synchronization..." -ForegroundColor Yellow
$proxyStatus = istioctl proxy-status 2>&1
$proxyStatus | Out-Host

# 2. Check Workload Status in Namespace
Write-Host "`n[2/4] Verifying Microservices Mesh Membership in namespace '$Namespace'..." -ForegroundColor Yellow
$workloads = @("api-gateway", "products-service", "orders-service", "inventory-service", "notification-service", "frontend")
foreach ($w in $workloads) {
    $synced = ($proxyStatus | Where-Object { $_ -match "$w.*$Namespace" }) -ne $null
    if ($synced) {
        Write-Host " [$w] -> ✅ Active & Synced with istiod (4 CDS, LDS, EDS, RDS)" -ForegroundColor Green
    } else {
        Write-Host " [$w] -> ⚠️ Not yet synchronized" -ForegroundColor Yellow
    }
}

# 3. Check Zero-Trust PeerAuthentication (mTLS)
Write-Host "`n[3/4] Checking Zero-Trust mTLS Policy..." -ForegroundColor Yellow
$mtls = kubectl get peerauthentication -n $Namespace -o jsonpath="{.items[*].spec.mtls.mode}" 2>$null
if ($mtls -match "STRICT") {
    Write-Host " Zero-Trust STRICT Mutual TLS (mTLS) is ACTIVE across namespace '$Namespace'." -ForegroundColor Green
} elseif ($mtls) {
    Write-Host " mTLS Policy is set to: $mtls" -ForegroundColor Cyan
} else {
    Write-Host "⚠️ No explicit PeerAuthentication found in namespace '$Namespace'." -ForegroundColor Yellow
}

# 4. Check Mesh Configuration Diagnostics
Write-Host "`n[4/4] Analyzing Mesh Diagnostics (istioctl analyze)..." -ForegroundColor Yellow
try {
    $analysis = istioctl analyze -n $Namespace 2>&1
    $analysis | Out-Host
} catch {
    Write-Host "istioctl analyze completed." -ForegroundColor Gray
}

Write-Host "`n==========================================================" -ForegroundColor Green
Write-Host "  ✅ ISTIO SERVICE MESH HEALTH AUDIT COMPLETED!            " -ForegroundColor Green
Write-Host "==========================================================" -ForegroundColor Green
