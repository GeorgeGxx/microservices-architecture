<#
.SYNOPSIS
    Stops and cleans up Microservices Architecture resources in Minikube (PowerShell).
.DESCRIPTION
    1. Removes microservice workloads, frontend, and services.
    2. Removes stateful infrastructure (Postgres, Redis, Kafka, Keycloak, Prometheus, Tempo, Loki, Alloy).
    3. Manages Minikube lifecycle (stop or purge).
    
    Usage:
      .\scripts\stop-minikube.ps1              # Deletes K8s workloads and stops Minikube VM
      .\scripts\stop-minikube.ps1 -Purge       # Deletes all resources and completely destroys Minikube cluster
      .\scripts\stop-minikube.ps1 -KeepCluster # Deletes pods/services while keeping Minikube running
#>

param (
    [Parameter(Mandatory = $false)]
    [switch]$Purge,

    [Parameter(Mandatory = $false)]
    [switch]$KeepCluster
)

$ErrorActionPreference = "Continue"

Write-Host "`n=======================================================" -ForegroundColor Cyan
Write-Host "🛑 STOPPING AND CLEANING UP MINIKUBE WORKLOADS" -ForegroundColor Cyan
Write-Host "=======================================================`n" -ForegroundColor Cyan

# 1. Delete Microservice Workloads (Frontend + Backend)
Write-Host "🗑️ [1/3] Deleting microservices and frontend from Kubernetes..." -ForegroundColor Yellow
if (Test-Path "./k8s/minikube/services/") {
    kubectl delete -f ./k8s/minikube/services/ --ignore-not-found=true
}

# 2. Delete Infrastructure & Security Resources
Write-Host "`n🗑️ [2/3] Deleting infrastructure (Vault, Kiali, Postgres, Redis, Kafka, Keycloak, Observability)..." -ForegroundColor Yellow
if (Test-Path "./k8s/minikube/vault/vault-dev.yaml") {
    kubectl delete -f ./k8s/minikube/vault/vault-dev.yaml --ignore-not-found=true 2>$null
}
if (Test-Path "./k8s/istio/04-kiali.yaml") {
    kubectl delete -f ./k8s/istio/04-kiali.yaml --ignore-not-found=true 2>$null
}
if (Test-Path "./k8s/minikube/infra/") {
    kubectl delete -f ./k8s/minikube/infra/ --ignore-not-found=true
}

# 3. Minikube Lifecycle Management
Write-Host "`n⏸️ [3/3] Managing Minikube cluster state..." -ForegroundColor Yellow
if ($Purge) {
    Write-Host "  💣 Completely destroying Minikube cluster (-Purge)..." -ForegroundColor Red
    minikube delete
} elseif ($KeepCluster) {
    Write-Host "  ✨ Minikube cluster kept running (-KeepCluster)." -ForegroundColor Green
} else {
    Write-Host "  ⏹️ Gracefully stopping Minikube cluster (minikube stop)..." -ForegroundColor Cyan
    minikube stop
}

Write-Host "`n=======================================================" -ForegroundColor Cyan
Write-Host "✅ ALL WORKLOADS STOPPED AND CLEANED UP SUCCESSFULLY!" -ForegroundColor Cyan
Write-Host "=======================================================`n" -ForegroundColor Cyan
