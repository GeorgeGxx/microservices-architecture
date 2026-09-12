# ==============================================================================
# Unified Azure Operations Manager (scripts/cloud/azure/manage-azure.ps1)
# Unifies:
#   1. ACR Authentication (formerly acr-login.ps1)
#   2. AKS Credentials & Helm Deployment (formerly deploy-aks.ps1)
# Environments: dev, staging, prod
# ==============================================================================
[CmdletBinding()]
param (
    [Parameter(Position = 0)]
    [ValidateSet("all", "deploy", "login", "credentials", "status", "help")]
    [string]$Action = "all",

    [Parameter(Position = 1)]
    [ValidateSet("dev", "staging", "prod")]
    [string]$Environment = "staging",

    [Parameter(Mandatory = $false)]
    [string]$AcrName = "",

    [Parameter(Mandatory = $false)]
    [string]$ResourceGroup = "",

    [Parameter(Mandatory = $false)]
    [string]$ClusterName = ""
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$root = Resolve-Path (Join-Path $PSScriptRoot "..\..\..")
$k8sAksDir = Join-Path $root "k8s\aks"
$umbrellaDir = Join-Path $root "helm\microservices-umbrella"
$valuesFile = Join-Path $root "helm\values\values-aks-$Environment.yaml"

# Default names based on environment
if (-not $ResourceGroup) {
    $ResourceGroup = "msa-azure-$Environment-rg"
}
if (-not $ClusterName) {
    $ClusterName = "msa-azure-$Environment-aks"
}
if (-not $AcrName) {
    $AcrName = "msaacr$Environment"
}

function Show-Banner {
    param([string]$Subtitle)
    Write-Host ""
    Write-Host "================================================================================" -ForegroundColor Cyan
    Write-Host " ☁️  UNIFIED AZURE CLOUD OPERATIONS MANAGER" -ForegroundColor Cyan
    Write-Host " Environment: [$($Environment.ToUpper())] | Action: [$Subtitle]" -ForegroundColor Yellow
    Write-Host " Resource Group: $ResourceGroup | AKS Cluster: $ClusterName" -ForegroundColor DarkGray
    Write-Host "================================================================================" -ForegroundColor Cyan
}

function Invoke-AcrLogin {
    Write-Host "`n[+] Authenticating Docker with Azure Container Registry: $AcrName..." -ForegroundColor Yellow
    az acr login --name $AcrName
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  [OK] Authenticated with ACR: $AcrName.azurecr.io" -ForegroundColor Green
    } else {
        Write-Error "ACR authentication failed. Make sure you are logged into Azure CLI (az login)."
    }
}

function Invoke-AksCredentials {
    Write-Host "`n[+] Fetching AKS credentials and updating local kubeconfig..." -ForegroundColor Yellow
    az aks get-credentials --resource-group $ResourceGroup --name $ClusterName --overwrite-existing
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  [OK] Kubeconfig updated for cluster '$ClusterName'." -ForegroundColor Green
    } else {
        Write-Error "Failed to fetch credentials for AKS cluster: $ClusterName"
    }
}

function Invoke-AksDeploy {
    # 1. Update Kubeconfig
    Invoke-AksCredentials

    # 2. Apply StorageClass and Ingress
    Write-Host "`n[+] Applying Azure StorageClass and Traefik Ingress manifests..." -ForegroundColor Yellow
    $sc = Join-Path $k8sAksDir "storageclass.yaml"
    $ing = Join-Path $k8sAksDir "ingress.yaml"
    if (Test-Path $sc) { kubectl apply -f $sc }
    if (Test-Path $ing) { kubectl apply -f $ing }

    # 3. Helm Deployment
    Write-Host "`n[+] Deploying microservices via Helm Umbrella Chart..." -ForegroundColor Yellow
    $targetNamespace = switch ($Environment) {
        "dev"     { "dev" }
        "staging" { "staging" }
        "prod"    { "production" }
    }
    kubectl create namespace $targetNamespace --dry-run=client -o yaml | kubectl apply -f - | Out-Null

    if (Test-Path $valuesFile) {
        helm upgrade --install microservices $umbrellaDir -f $valuesFile --namespace $targetNamespace
        Write-Host "`n  [OK] Helm deployment completed successfully for $ClusterName in namespace '$targetNamespace'." -ForegroundColor Green
    } else {
        Write-Error "Values file not found: $valuesFile"
    }
}

switch ($Action) {
    "login" {
        Show-Banner "ACR Authentication"
        Invoke-AcrLogin
    }
    "credentials" {
        Show-Banner "AKS Credentials"
        Invoke-AksCredentials
    }
    "deploy" {
        Show-Banner "AKS Cluster Deployment"
        Invoke-AksDeploy
    }
    "all" {
        Show-Banner "Full Azure Pipeline (Login + Credentials + Deploy)"
        try {
            Invoke-AcrLogin
        } catch {
            Write-Host "  [WARN] Continuing deployment without direct ACR Docker login." -ForegroundColor Yellow
        }
        Invoke-AksDeploy
    }
    "status" {
        Show-Banner "Azure AKS & Resource Status"
        az aks show --resource-group $ResourceGroup --name $ClusterName --query "{Name:name,Status:provisioningState,Nodes:agentPoolProfiles[0].count,K8sVersion:kubernetesVersion}" -o table 2>$null
        kubectl get nodes -o wide 2>$null
    }
    default {
        Show-Banner "CLI Help Reference"
        Write-Host "Usage: .\manage-azure.ps1 [-Action all|deploy|login|credentials|status] [-Environment dev|staging|prod] [-AcrName <name>]" -ForegroundColor White
    }
}
