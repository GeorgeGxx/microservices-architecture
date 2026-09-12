# ==============================================================================
# Unified Google Cloud Platform Operations Manager (scripts/cloud/gcp/manage-gcp.ps1)
# Unifies:
#   1. Google Artifact Registry (GAR) Authentication (formerly gar-login.ps1)
#   2. GKE Credentials & Helm Deployment (formerly deploy-gke.ps1)
#   3. GKE Persistent Disk Snapshot FinOps Lifecycle (formerly gke-disk-cleanup.py)
# Environments: dev, staging, prod
# ==============================================================================
[CmdletBinding()]
param (
    [Parameter(Position = 0)]
    [ValidateSet("all", "deploy", "login", "credentials", "disk-cleanup", "status", "help")]
    [string]$Action = "all",

    [Parameter(Position = 1)]
    [ValidateSet("dev", "staging", "prod")]
    [string]$Environment = "staging",

    [Parameter(Mandatory = $false)]
    [string]$GcpRegion = "us-central1",

    [Parameter(Mandatory = $false)]
    [string]$GcpProject = "",

    [Parameter(Mandatory = $false)]
    [string]$ClusterName = "",

    [Parameter(Mandatory = $false)]
    [int]$RetentionDays = 30,

    [switch]$DryRun = $false
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$root = Resolve-Path (Join-Path $PSScriptRoot "..\..\..")
$k8sGkeDir = Join-Path $root "k8s\gke"
$umbrellaDir = Join-Path $root "helm\microservices-umbrella"
$valuesFile = Join-Path $root "helm\values\values-gke-$Environment.yaml"

if (-not $ClusterName) {
    $ClusterName = "msa-gcp-$Environment-gke"
}
if (-not $GcpProject) {
    $GcpProject = "msa-gcp-$Environment"
}

$garRegistry = "$GcpRegion-docker.pkg.dev"

function Show-Banner {
    param([string]$Subtitle)
    Write-Host ""
    Write-Host "================================================================================" -ForegroundColor Cyan
    Write-Host " 🇬 UNIFIED GOOGLE CLOUD (GCP) OPERATIONS MANAGER" -ForegroundColor Cyan
    Write-Host " Environment: [$($Environment.ToUpper())] | Action: [$Subtitle]" -ForegroundColor Yellow
    Write-Host " Region: $GcpRegion | Project: $GcpProject | GKE Cluster: $ClusterName" -ForegroundColor DarkGray
    Write-Host "================================================================================" -ForegroundColor Cyan
}

function Invoke-GarLogin {
    Write-Host "`n[+] Authenticating Docker with Google Artifact Registry ($garRegistry)..." -ForegroundColor Yellow
    gcloud auth configure-docker $garRegistry --quiet
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  [OK] Authenticated with Google Artifact Registry: $garRegistry" -ForegroundColor Green
    } else {
        Write-Error "GAR authentication failed. Ensure gcloud CLI is authenticated (gcloud auth login)."
    }
}

function Invoke-GkeCredentials {
    Write-Host "`n[+] Fetching GKE credentials and updating local kubeconfig..." -ForegroundColor Yellow
    if ($GcpProject) {
        gcloud container clusters get-credentials $ClusterName --region $GcpRegion --project $GcpProject
    } else {
        gcloud container clusters get-credentials $ClusterName --region $GcpRegion
    }
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  [OK] Kubeconfig updated for GKE cluster '$ClusterName'." -ForegroundColor Green
    } else {
        Write-Error "Failed to fetch credentials for GKE cluster: $ClusterName"
    }
}

function Invoke-GkeDeploy {
    # 1. Update Kubeconfig
    Invoke-GkeCredentials

    # 2. Apply StorageClass and Ingress
    Write-Host "`n[+] Applying GKE StorageClass and Ingress manifests..." -ForegroundColor Yellow
    $sc = Join-Path $k8sGkeDir "storageclass.yaml"
    $ing = Join-Path $k8sGkeDir "ingress.yaml"
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

function Invoke-DiskCleanup {
    Write-Host "`n[+] Running FinOps Persistent Disk Snapshot Audit (Retention: $RetentionDays days)..." -ForegroundColor Yellow
    $cutoff = (Get-Date).AddDays(-$RetentionDays).ToString("yyyy-MM-ddTHH:mm:ssZ")
    
    $projectArg = if ($GcpProject) { "--project=$GcpProject" } else { "" }
    $snapshots = gcloud compute snapshots list $projectArg --format="json" 2>$null | ConvertFrom-Json
    
    if (-not $snapshots -or $snapshots.Count -eq 0) {
        Write-Host "  [OK] No orphaned snapshots found for project '$GcpProject'." -ForegroundColor Green
        return
    }

    $deletedCount = 0
    foreach ($snap in $snapshots) {
        $creation = [DateTime]::Parse($snap.creationTimestamp)
        $ageDays = ((Get-Date) - $creation).Days
        if ($ageDays -gt $RetentionDays) {
            Write-Host "  • Snapshot: $($snap.name) (Age: $ageDays days, Size: $($snap.diskSizeGb) GB)" -ForegroundColor Yellow
            if ($DryRun) {
                Write-Host "    [DRY-RUN] Would delete snapshot $($snap.name)" -ForegroundColor Gray
            } else {
                Write-Host "    Deleting $($snap.name)..." -ForegroundColor Red
                gcloud compute snapshots delete $snap.name --quiet $projectArg
                $deletedCount++
            }
        }
    }
    Write-Host "`n  [OK] FinOps snapshot audit completed. Total processed: $($snapshots.Count), Purged: $deletedCount." -ForegroundColor Green
}

switch ($Action) {
    "login" {
        Show-Banner "GAR Authentication"
        Invoke-GarLogin
    }
    "credentials" {
        Show-Banner "GKE Credentials"
        Invoke-GkeCredentials
    }
    "deploy" {
        Show-Banner "GKE Cluster Deployment"
        Invoke-GkeDeploy
    }
    "disk-cleanup" {
        Show-Banner "FinOps Disk Snapshot Lifecycle"
        Invoke-DiskCleanup
    }
    "all" {
        Show-Banner "Full GCP Pipeline (Login + Credentials + Deploy)"
        try {
            Invoke-GarLogin
        } catch {
            Write-Host "  [WARN] Continuing deployment without direct GAR Docker configuration." -ForegroundColor Yellow
        }
        Invoke-GkeDeploy
    }
    "status" {
        Show-Banner "GKE Cluster & Node Status"
        gcloud container clusters describe $ClusterName --region $GcpRegion --format="table(name,status,currentNodeCount,currentMasterVersion)" 2>$null
        kubectl get nodes -o wide 2>$null
    }
    default {
        Show-Banner "CLI Help Reference"
        Write-Host "Usage: .\manage-gcp.ps1 [-Action all|deploy|login|credentials|disk-cleanup|status] [-Environment dev|staging|prod] [-GcpRegion <reg>]" -ForegroundColor White
    }
}
