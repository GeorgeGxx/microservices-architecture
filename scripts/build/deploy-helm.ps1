param (
    [Parameter(Mandatory = $true, HelpMessage = "Target environment: minikube, eks-dev, aks-dev, gke-dev, eks-prod, aks-prod, gke-prod")]
    [string]$Environment,

    [Parameter(Mandatory = $false)]
    [string]$Namespace = "default"
)

$ErrorActionPreference = "Stop"

$rootDir = (Get-Item $PSScriptRoot).Parent.Parent.FullName
$valuesFile = Join-Path $rootDir "helm\values\values-$Environment.yaml"
$chartDir = Join-Path $rootDir "helm\microservices-umbrella"

if (-not (Test-Path $valuesFile)) {
    Write-Error "Values file not found: $valuesFile"
}

Write-Host "=======================================================" -ForegroundColor Cyan
Write-Host " DEPLOYING HELM UMBRELLA CHART - ENV: $Environment" -ForegroundColor Cyan
Write-Host " Chart: $chartDir | Values: $valuesFile" -ForegroundColor Cyan
Write-Host "=======================================================`n" -ForegroundColor Cyan

$currentContext = kubectl config current-context 2>$null
Write-Host "Current kubectl context: $currentContext" -ForegroundColor Yellow

kubectl create namespace $Namespace --dry-run=client -o yaml | kubectl apply -f -

Write-Host "`nUpgrading / Installing Helm release 'microservices'..." -ForegroundColor Cyan
helm upgrade --install microservices $chartDir --namespace $Namespace --values $valuesFile --wait --timeout 5m

Write-Host "`n Helm deployment completed successfully!" -ForegroundColor Green
helm list -n $Namespace
