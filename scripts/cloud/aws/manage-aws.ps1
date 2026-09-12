# ==============================================================================
# Unified Amazon Web Services (AWS) Operations Manager (scripts/cloud/aws/manage-aws.ps1)
# Unifies:
#   1. Amazon ECR Docker Authentication (formerly ecr-login.ps1)
#   2. Amazon EKS Credentials & Helm Deployment (formerly deploy-eks.ps1)
#   3. AWS Well-Architected Governance & Audit Trigger (delegates to audit-aws.py)
# Environments: dev, staging, prod
# ==============================================================================
[CmdletBinding()]
param (
    [Parameter(Position = 0)]
    [ValidateSet("all", "deploy", "login", "credentials", "audit", "status", "help")]
    [string]$Action = "all",

    [Parameter(Position = 1)]
    [ValidateSet("dev", "staging", "prod")]
    [string]$Environment = "staging",

    [Parameter(Mandatory = $false)]
    [string]$AwsRegion = "us-east-1",

    [Parameter(Mandatory = $false)]
    [string]$AccountId = "",

    [Parameter(Mandatory = $false)]
    [string]$ClusterName = "",

    [Parameter(Mandatory = $false)]
    [string]$AuditModule = "all"
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$root = Resolve-Path (Join-Path $PSScriptRoot "..\..\..")
$k8sEksDir = Join-Path $root "k8s\eks"
$umbrellaDir = Join-Path $root "helm\microservices-umbrella"
$valuesFile = Join-Path $root "helm\values\values-eks-$Environment.yaml"
$auditScript = Join-Path $PSScriptRoot "audit-aws.py"

if (-not $ClusterName) {
    $ClusterName = "msa-aws-$Environment-eks"
}

function Show-Banner {
    param([string]$Subtitle)
    Write-Host ""
    Write-Host "================================================================================" -ForegroundColor Cyan
    Write-Host " 🟧 UNIFIED AMAZON WEB SERVICES (AWS) OPERATIONS MANAGER" -ForegroundColor Cyan
    Write-Host " Environment: [$($Environment.ToUpper())] | Action: [$Subtitle]" -ForegroundColor Yellow
    Write-Host " Region: $AwsRegion | Cluster: $ClusterName" -ForegroundColor DarkGray
    Write-Host "================================================================================" -ForegroundColor Cyan
}

function Get-AwsAccountId {
    if ($AccountId) { return $AccountId }
    try {
        $id = (aws sts get-caller-identity --query "Account" --output text 2>$null)
        if ($id) { return $id.Trim() }
    } catch {}
    return "123456789012"
}

function Invoke-EcrLogin {
    $acc = Get-AwsAccountId
    $ecrRegistry = "$acc.dkr.ecr.$AwsRegion.amazonaws.com"
    Write-Host "`n[+] Authenticating Docker with Amazon ECR ($ecrRegistry)..." -ForegroundColor Yellow
    aws ecr get-login-password --region $AwsRegion | docker login --username AWS --password-stdin $ecrRegistry
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  [OK] Authenticated with Amazon ECR: $ecrRegistry" -ForegroundColor Green
    } else {
        Write-Error "Amazon ECR authentication failed. Verify AWS credentials and permissions."
    }
}

function Invoke-EksCredentials {
    Write-Host "`n[+] Fetching EKS credentials and updating local kubeconfig..." -ForegroundColor Yellow
    aws eks update-kubeconfig --region $AwsRegion --name $ClusterName
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  [OK] Kubeconfig updated for EKS cluster '$ClusterName'." -ForegroundColor Green
    } else {
        Write-Error "Failed to fetch credentials for EKS cluster: $ClusterName"
    }
}

function Invoke-EksDeploy {
    # 1. Update Kubeconfig
    Invoke-EksCredentials

    # 2. Apply StorageClass and Ingress
    Write-Host "`n[+] Applying AWS StorageClass (GP3) and Ingress manifests..." -ForegroundColor Yellow
    $sc = Join-Path $k8sEksDir "storageclass.yaml"
    $ing = Join-Path $k8sEksDir "ingress.yaml"
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

function Invoke-AwsAudit {
    Write-Host "`n[+] Running AWS Well-Architected Governance & Security Audit (Module: $AuditModule)..." -ForegroundColor Yellow
    if (Test-Path $auditScript) {
        python $auditScript --module $AuditModule --region $AwsRegion
    } else {
        Write-Error "Audit script not found: $auditScript"
    }
}

switch ($Action) {
    "login" {
        Show-Banner "Amazon ECR Authentication"
        Invoke-EcrLogin
    }
    "credentials" {
        Show-Banner "Amazon EKS Credentials"
        Invoke-EksCredentials
    }
    "deploy" {
        Show-Banner "Amazon EKS Cluster Deployment"
        Invoke-EksDeploy
    }
    "audit" {
        Show-Banner "Well-Architected Governance & Security Audit"
        Invoke-AwsAudit
    }
    "all" {
        Show-Banner "Full AWS Pipeline (Login + Credentials + Deploy)"
        try {
            Invoke-EcrLogin
        } catch {
            Write-Host "  [WARN] Continuing deployment without direct ECR Docker login." -ForegroundColor Yellow
        }
        Invoke-EksDeploy
    }
    "status" {
        Show-Banner "Amazon EKS Cluster & Node Status"
        aws eks describe-cluster --region $AwsRegion --name $ClusterName --query "cluster.{Name:name,Status:status,Version:version,Endpoint:endpoint}" --output table 2>$null
        kubectl get nodes -o wide 2>$null
    }
    default {
        Show-Banner "CLI Help Reference"
        Write-Host "Usage: .\manage-aws.ps1 [-Action all|deploy|login|credentials|audit|status] [-Environment dev|staging|prod] [-AwsRegion <reg>] [-AuditModule <mod>]" -ForegroundColor White
    }
}
