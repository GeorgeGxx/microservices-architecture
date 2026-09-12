# ==============================================================================
# Teardown / Stop Local DevSecOps Platform (Frees 12GB RAM and 12 CPUs)
# ==============================================================================
[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [switch]$DeleteCluster = $false,

    [Parameter(Mandatory = $false)]
    [switch]$CleanTerraformState = $false
)

Write-Host "================================================================================" -ForegroundColor Cyan
Write-Host "🛑 TEARDOWN: Local DevSecOps Ecosystem (Minikube + Tools)" -ForegroundColor Cyan
Write-Host "================================================================================" -ForegroundColor Cyan

# 1. Stop background port-forward tunnels
Write-Host "`n🔌 Closing all background port-forward tunnels..." -ForegroundColor Yellow
Get-Process -Name "kubectl" -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -like "*port-forward*" } | Stop-Process -Force -ErrorAction SilentlyContinue
Write-Host "✅ All localhost tunnels closed." -ForegroundColor Green

# 2. Complete Deletion OR Graceful Pause
if ($DeleteCluster) {
    Write-Host "`n🗑️ Completely deleting the Minikube cluster and all volumes (--delete --purge)..." -ForegroundColor Red
    minikube delete --all --purge
    
    if ($CleanTerraformState) {
        Write-Host "🧹 Cleaning Terraform local state in terraform/environments/local-minikube..." -ForegroundColor Yellow
        $tfStateDir = Join-Path $PSScriptRoot "..\..\terraform\environments\local-minikube"
        Remove-Item "$tfStateDir\terraform.tfstate*" -Force -ErrorAction SilentlyContinue
        Remove-Item "$tfStateDir\.terraform.lock.hcl" -Force -ErrorAction SilentlyContinue
    }
    
    Write-Host "`n🎉 Minikube cluster, storage, and namespaces completely destroyed." -ForegroundColor Green
} else {
    Write-Host "`n⏸️ Pausing and stopping Minikube (releases 12 GB RAM & 12 CPUs)..." -ForegroundColor Yellow
    minikube stop
    Write-Host "✅ Minikube stopped. Your cluster state, images, and data are safely preserved." -ForegroundColor Green
    Write-Host "💡 To start everything up again later, just run: .\platform-minikube.ps1 up" -ForegroundColor Cyan
}

Write-Host "`n================================================================================" -ForegroundColor Green
Write-Host "💻 All hardware resources on your AMD Ryzen 7 and 32 GB RAM are fully released." -ForegroundColor Green
Write-Host "================================================================================" -ForegroundColor Green
