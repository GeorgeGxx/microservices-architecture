param (
    [Parameter(Mandatory = $false)]
    [ValidateSet("dev", "staging", "prod")]
    [string]$Environment = "dev",

    [Parameter(Mandatory = $false)]
    [string]$AwsRegion = "us-east-1",

    [Parameter(Mandatory = $false)]
    [string]$ClusterName
)

$ErrorActionPreference = "Stop"

if (-not $ClusterName) {
    $ClusterName = "msa-aws-$Environment-eks"
}

Write-Host "=======================================================" -ForegroundColor Cyan
Write-Host " DEPLOYING TO AWS EKS CLUSTER: $ClusterName" -ForegroundColor Cyan
Write-Host " Region: $AwsRegion | Environment: $Environment" -ForegroundColor Cyan
Write-Host "=======================================================`n" -ForegroundColor Cyan

# 1. Update Kubeconfig from AWS EKS
Write-Host "[1/3] Fetching EKS credentials and updating local kubeconfig..." -ForegroundColor Yellow
aws eks update-kubeconfig --region $AwsRegion --name $ClusterName

# 2. Apply StorageClass and Ingress manifests
Write-Host "`n[2/3] Applying AWS StorageClass (GP3) and Ingress..." -ForegroundColor Yellow
if (Test-Path "./k8s/eks/storageclass.yaml") {
    kubectl apply -f ./k8s/eks/storageclass.yaml
}
if (Test-Path "./k8s/eks/ingress.yaml") {
    kubectl apply -f ./k8s/eks/ingress.yaml
}

# 3. Helm Deployment
Write-Host "`n[3/3] Deploying microservices via Helm..." -ForegroundColor Yellow
$ValuesFile = "./helm/values/values-eks-$Environment.yaml"
if (Test-Path $ValuesFile) {
    helm upgrade --install microservices ./helm/microservices-umbrella -f $ValuesFile --namespace default
    Write-Host "`n Helm deployment completed successfully for $ClusterName." -ForegroundColor Green
} else {
    Write-Error "Values file not found: $ValuesFile"
}
