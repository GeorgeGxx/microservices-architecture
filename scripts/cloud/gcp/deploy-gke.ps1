param (
    [Parameter(Mandatory = $false)]
    [ValidateSet("dev", "staging", "prod")]
    [string]$Environment = "dev",

    [Parameter(Mandatory = $false)]
    [string]$GcpRegion = "us-central1",

    [Parameter(Mandatory = $false)]
    [string]$GcpProject,

    [Parameter(Mandatory = $false)]
    [string]$ClusterName
)

$ErrorActionPreference = "Stop"

if (-not $ClusterName) {
    $ClusterName = "msa-gcp-$Environment-gke"
}

Write-Host "=======================================================" -ForegroundColor Cyan
Write-Host " DEPLOYING TO GOOGLE CLOUD GKE CLUSTER: $ClusterName" -ForegroundColor Cyan
Write-Host " Region: $GcpRegion | Environment: $Environment" -ForegroundColor Cyan
Write-Host "=======================================================`n" -ForegroundColor Cyan

# 1. Update Kubeconfig from Google Cloud GKE
Write-Host "[1/3] Fetching GKE credentials and updating local kubeconfig..." -ForegroundColor Yellow
if ($GcpProject) {
    gcloud container clusters get-credentials $ClusterName --region $GcpRegion --project $GcpProject
} else {
    gcloud container clusters get-credentials $ClusterName --region $GcpRegion
}

# 2. Apply StorageClass and Ingress manifests
Write-Host "`n[2/3] Applying GKE StorageClass and Ingress..." -ForegroundColor Yellow
if (Test-Path "./k8s/gke/storageclass.yaml") {
    kubectl apply -f ./k8s/gke/storageclass.yaml
}
if (Test-Path "./k8s/gke/ingress.yaml") {
    kubectl apply -f ./k8s/gke/ingress.yaml
}

# 3. Helm Deployment
Write-Host "`n[3/3] Deploying microservices via Helm..." -ForegroundColor Yellow
$ValuesFile = "./helm/values/values-gke-$Environment.yaml"
if (Test-Path $ValuesFile) {
    helm upgrade --install microservices ./helm/microservices-umbrella -f $ValuesFile --namespace default
    Write-Host "`n Helm deployment completed successfully for $ClusterName." -ForegroundColor Green
} else {
    Write-Error "Values file not found: $ValuesFile"
}
