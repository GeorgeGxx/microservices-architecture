param (
    [Parameter(Mandatory = $false)]
    [ValidateSet("dev", "prod")]
    [string]$Environment = "dev",

    [Parameter(Mandatory = $false)]
    [string]$ResourceGroup,

    [Parameter(Mandatory = $false)]
    [string]$ClusterName
)

$ErrorActionPreference = "Stop"

if (-not $ResourceGroup) {
    $ResourceGroup = "msa-azure-$Environment-rg"
}

if (-not $ClusterName) {
    $ClusterName = "msa-azure-$Environment-aks"
}

Write-Host "=======================================================" -ForegroundColor Cyan
Write-Host " DEPLOYING TO AZURE AKS CLUSTER: $ClusterName" -ForegroundColor Cyan
Write-Host " Resource Group: $ResourceGroup | Environment: $Environment" -ForegroundColor Cyan
Write-Host "=======================================================`n" -ForegroundColor Cyan

# 1. Update Kubeconfig from Azure AKS
Write-Host "[1/3] Fetching AKS credentials and updating local kubeconfig..." -ForegroundColor Yellow
az aks get-credentials --resource-group $ResourceGroup --name $ClusterName --overwrite-existing

# 2. Apply StorageClass and Ingress manifests
Write-Host "`n[2/3] Applying Azure StorageClass and Traefik Ingress..." -ForegroundColor Yellow
kubectl apply -f ./k8s/aks/storageclass.yaml
kubectl apply -f ./k8s/aks/ingress.yaml

# 3. Helm Deployment
Write-Host "`n[3/3] Deploying microservices via Helm..." -ForegroundColor Yellow
$ValuesFile = "./helm/values/values-aks-$Environment.yaml"
if (Test-Path $ValuesFile) {
    helm upgrade --install microservices ./helm/microservices-umbrella -f $ValuesFile --namespace default
    Write-Host "`nHelm deployment completed successfully for $ClusterName." -ForegroundColor Green
} else {
    Write-Error "Values file not found: $ValuesFile"
}
