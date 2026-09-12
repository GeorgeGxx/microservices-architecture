# ==============================================================================
# Platform GCP CLI Orchestrator (Version: Google Cloud Platform | Environments: dev, staging, prod)
# Git Branch Correlation:
#   - 'develop'     -> 'dev' environment (GKE Autopilot burstable, namespace: 'dev')
#   - 'staging'     -> 'staging' environment (Medium performance, namespace: 'staging')
#   - 'main/master' -> 'prod' environment (High performance HA, namespace: 'production')
#
# Modules Managed: vpc, gke, cloudsql, memorystore, managed_kafka, gcs, kms,
#                  workload_identity, cloud_armor_lb, cloud_cdn, cloud_monitoring, cloud_dns
# CI/CD Engine: Bitbucket Pipelines (Single Unified Pipeline with 12+ Stages + Rollback)
# ==============================================================================
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet("plan", "apply", "destroy", "rollback", "status", "unlock", "cost", "help")]
    [string]$Action = "plan",

    [Parameter(Position = 1)]
    [ValidateSet("dev", "staging", "prod")]
    [string]$Environment = "staging",

    [string]$ProjectId = "",
    [string]$Region = "us-central1",
    [switch]$AutoApprove = $false,
    [string]$LockId = ""
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$root = $PSScriptRoot
$gcpTfDir = Join-Path $root "terraform\environments\gcp"

function Show-Header {
    param([string]$Title)
    Write-Host ""
    Write-Host "================================================================================" -ForegroundColor Green
    Write-Host " ☁️  GOOGLE CLOUD PLATFORM (GCP) ORCHESTRATOR" -ForegroundColor Green
    Write-Host " ▶ Action: $Title | Environment: [$($Environment.ToUpper())] | Region: $Region" -ForegroundColor White
    Write-Host "================================================================================" -ForegroundColor Green
}

# Namespace and branch mappings
$targetNamespace = switch ($Environment) {
    "dev"     { "dev" }
    "staging" { "staging" }
    "prod"    { "production" }
}

$branchMapping = switch ($Environment) {
    "dev"     { "develop" }
    "staging" { "staging" }
    "prod"    { "main / master" }
}

$clusterName = "msa-gcp-$Environment-gke"
$gcpProject = if ($ProjectId) { $ProjectId } else { "msa-gcp-$Environment" }

switch ($Action) {
    "plan" {
        Show-Header "Terraform Plan (12 GCP Modules)"
        Write-Host "Correlated Branch: $branchMapping | GKE Namespace: $targetNamespace" -ForegroundColor Cyan
        Push-Location $gcpTfDir
        try {
            terraform fmt -check
            terraform init -backend=false
            terraform workspace select -or-create $Environment || true
            terraform validate
            $varFile = "${Environment}/terraform.tfvars"
            if (Test-Path $varFile) {
                Write-Host "Executing Terraform Plan with -var-file=$varFile..." -ForegroundColor Green
                terraform plan -var-file=$varFile -no-color
            } else {
                terraform plan -no-color
            }
        } finally {
            Pop-Location
        }
    }

    "apply" {
        Show-Header "Terraform Apply (Provision GCP Infrastructure)"
        Write-Host "Provisioning GKE Autopilot, VPC, Cloud SQL, Memorystore, Cloud Armor in '$Environment'..." -ForegroundColor Cyan
        Push-Location $gcpTfDir
        try {
            terraform workspace select -or-create $Environment || true
            $varFile = "${Environment}/terraform.tfvars"
            $approveArg = if ($AutoApprove) { "-auto-approve" } else { "" }
            
            if (Test-Path $varFile) {
                terraform apply -var-file=$varFile $approveArg
            } else {
                terraform apply $approveArg
            }

            if ($LASTEXITCODE -eq 0) {
                Write-Host "`n[OK] GCP Infrastructure provisioned successfully." -ForegroundColor Green
                Write-Host "Ensuring destination namespace '$targetNamespace' exists in GKE..." -ForegroundColor Cyan
                gcloud container clusters get-credentials $clusterName --region $Region --project $gcpProject 2>$null
                kubectl create namespace $targetNamespace --dry-run=client -o yaml | kubectl apply -f - 2>$null
            } else {
                Write-Error "Terraform Apply failed for GCP environment: $Environment"
            }
        } finally {
            Pop-Location
        }
    }

    "rollback" {
        Show-Header "Emergency Rollback & GCS State Unlock"
        Write-Host "Executing automated rollback for GCP environment: $Environment..." -ForegroundColor Red
        
        # 1. Force unlock GCS backend state if locked
        Push-Location $gcpTfDir
        try {
            Write-Host "Releasing Google Cloud Storage backend state lock..." -ForegroundColor Yellow
            if ($LockId) {
                terraform force-unlock -force $LockId
            } else {
                terraform force-unlock -force 0 2>$null || true
            }
        } finally {
            Pop-Location
        }

        # 2. Helm Rollback on GKE cluster
        Write-Host "`nExecuting Helm rollback on GKE namespace '$targetNamespace'..." -ForegroundColor Yellow
        gcloud container clusters get-credentials $clusterName --region $Region --project $gcpProject 2>$null
        if (Get-Command "helm" -ErrorAction SilentlyContinue) {
            helm rollback microservices --namespace $targetNamespace --wait --timeout 5m 2>$null
            if ($LASTEXITCODE -eq 0) {
                Write-Host "[OK] Helm rollback completed on GKE namespace '$targetNamespace'." -ForegroundColor Green
            } else {
                Write-Host "[WARN] Helm rollback executed with warnings." -ForegroundColor Yellow
            }
        }
    }

    "unlock" {
        Show-Header "Force Unlock GCP GCS Backend State"
        Push-Location $gcpTfDir
        try {
            $id = if ($LockId) { $LockId } else { "0" }
            terraform force-unlock -force $id
        } finally {
            Pop-Location
        }
    }

    "status" {
        Show-Header "GCP Infrastructure Status"
        Push-Location $gcpTfDir
        try {
            terraform workspace select -or-create $Environment || true
            terraform show -no-color | Select-Object -First 30
        } finally {
            Pop-Location
        }
        Write-Host "`nGKE Cluster Status in ${gcpProject}:" -ForegroundColor Cyan
        gcloud container clusters list --project $gcpProject 2>$null
    }

    "cost" {
        Show-Header "FinOps Cost Estimation for GCP $Environment"
        $costScript = Join-Path $root "scripts\cloud\terraform\local-cost-estimator.py"
        python $costScript --env $Environment
    }

    default {
        Show-Header "GCP Platform CLI Reference"
        Write-Host "Usage: .\platform-gcp.ps1 <Action> [Environment] [Options]" -ForegroundColor White
        Write-Host ""
        Write-Host "Actions:" -ForegroundColor Cyan
        Write-Host "  plan          Format, validate and plan GCP Terraform infrastructure"
        Write-Host "  apply         Provision GCP infrastructure (VPC, GKE, Cloud SQL, Memorystore, Cloud Armor, etc.)"
        Write-Host "  rollback      Execute automated emergency rollback and GCS state unlock"
        Write-Host "  unlock        Release stranded Terraform GCS state lock"
        Write-Host "  status        Display active Terraform state and GKE cluster status"
        Write-Host "  cost          Estimate cloud infrastructure costs via FinOps engine"
        Write-Host ""
        Write-Host "Environments:" -ForegroundColor Cyan
        Write-Host "  dev           Burstable tier (Branch: develop, Namespace: dev)"
        Write-Host "  staging       Medium performance tier (Branch: staging, Namespace: staging)"
        Write-Host "  prod          High performance HA tier (Branch: main/master, Namespace: production)"
    }
}
