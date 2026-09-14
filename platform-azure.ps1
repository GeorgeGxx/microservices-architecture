# ==============================================================================
# Platform Azure CLI Orchestrator (Version: Azure Cloud | Environments: dev, staging, prod)
# Git Branch Correlation:
#   - 'develop' -> 'dev' environment (Standard_D2s_v5 burstable, namespace: 'dev')
#   - 'staging' -> 'staging' environment (Medium performance, namespace: 'staging')
#   - 'master'  -> 'prod' environment (High performance HA, namespace: 'production')
#
# Modules Managed: vnet, aks, postgresql, redis, eventhubs, storage_account, keyvault,
#                  workload_identity, app_gateway, frontdoor, monitor, dns_zone
# CI/CD Engine: Azure DevOps (Single Unified Pipeline with 12+ Stages + Rollback)
# ==============================================================================
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet("plan", "apply", "destroy", "rollback", "status", "unlock", "cost", "help")]
    [string]$Action = "plan",

    [Parameter(Position = 1)]
    [ValidateSet("dev", "staging", "prod")]
    [string]$Environment = "staging",

    [string]$ResourceGroup = "",
    [switch]$AutoApprove = $false,
    [string]$LockId = ""
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$root = $PSScriptRoot
$azureTfDir = Join-Path $root "terraform\environments\azure"
$azdoDir = Join-Path $root "azure-devops"

function Show-Header {
    param([string]$Title)
    Write-Host ""
    Write-Host "================================================================================" -ForegroundColor Blue
    Write-Host " ☁️  AZURE CLOUD PLATFORM ORCHESTRATOR" -ForegroundColor Blue
    Write-Host " ▶ Action: $Title | Environment: [$($Environment.ToUpper())] | Resource Group: $rgName" -ForegroundColor White
    Write-Host "================================================================================" -ForegroundColor Blue
}

function Write-TargetSummary {
    param([string]$EnvironmentName, [string]$NamespaceName)
    Write-Host "Target: Azure | Branch: $branchMapping | Namespace: $NamespaceName | Environment: $EnvironmentName | Cluster: $clusterName" -ForegroundColor Cyan
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
    "prod"    { "master" }
}

$rgName = if ($ResourceGroup) { $ResourceGroup } else { "msa-azure-$Environment-rg" }
$clusterName = "msa-azure-$Environment-aks"

switch ($Action) {
    "plan" {
        Show-Header "Terraform Plan (12 Azure Modules)"
        Write-TargetSummary -EnvironmentName $Environment -NamespaceName $targetNamespace
        Push-Location $azureTfDir
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
        Show-Header "Terraform Apply (Provision Azure Infrastructure)"
        Write-TargetSummary -EnvironmentName $Environment -NamespaceName $targetNamespace
        Write-Host "Provisioning AKS, VNet, PostgreSQL Flexible, Redis, Key Vault, and App Gateway in '$Environment'..." -ForegroundColor Cyan
        Push-Location $azureTfDir
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
                Write-Host "`n[OK] Azure Infrastructure provisioned successfully." -ForegroundColor Green
                Write-Host "Ensuring destination namespace '$targetNamespace' exists in AKS..." -ForegroundColor Cyan
                az aks get-credentials --resource-group $rgName --name $clusterName --overwrite-existing 2>$null
                kubectl create namespace $targetNamespace --dry-run=client -o yaml | kubectl apply -f - 2>$null
            } else {
                Write-Error "Terraform Apply failed for Azure environment: $Environment"
            }
        } finally {
            Pop-Location
        }
    }

    "rollback" {
        Show-Header "Emergency Rollback & State Lease Unlock"
        Write-Host "Executing automated rollback for Azure environment: $Environment..." -ForegroundColor Red
        
        # 1. Force unlock Azure Storage Blob state lease if locked
        Push-Location $azureTfDir
        try {
            Write-Host "Releasing Azure Storage Blob backend state lease..." -ForegroundColor Yellow
            if ($LockId) {
                terraform force-unlock -force $LockId
            } else {
                terraform force-unlock -force 0 2>$null || true
            }
        } finally {
            Pop-Location
        }

        # 2. Helm Rollback on AKS cluster
        Write-Host "`nExecuting Helm rollback on AKS namespace '$targetNamespace'..." -ForegroundColor Yellow
        az aks get-credentials --resource-group $rgName --name $clusterName --overwrite-existing 2>$null
        if (Get-Command "helm" -ErrorAction SilentlyContinue) {
            helm rollback microservices --namespace $targetNamespace --wait --timeout 5m 2>$null
            if ($LASTEXITCODE -eq 0) {
                Write-Host "[OK] Helm rollback completed on namespace '$targetNamespace'." -ForegroundColor Green
            } else {
                Write-Host "[WARN] Helm rollback executed with warnings." -ForegroundColor Yellow
            }
        }
    }

    "unlock" {
        Show-Header "Force Unlock Azure Backend State"
        Push-Location $azureTfDir
        try {
            $id = if ($LockId) { $LockId } else { "0" }
            terraform force-unlock -force $id
        } finally {
            Pop-Location
        }
    }

    "status" {
        Show-Header "Azure Infrastructure Status"
        Write-TargetSummary -EnvironmentName $Environment -NamespaceName $targetNamespace
        Push-Location $azureTfDir
        try {
            terraform workspace select -or-create $Environment || true
            terraform show -no-color | Select-Object -First 30
        } finally {
            Pop-Location
        }
        Write-Host "`nAzure Resources in ${rgName}:" -ForegroundColor Cyan
        az resource list --resource-group $rgName --output table 2>$null
    }

    "cost" {
        Show-Header "FinOps Cost Estimation for Azure $Environment"
        $costScript = Join-Path $root "scripts\cloud\terraform\local-cost-estimator.py"
        python $costScript --env $Environment
    }

    default {
        Show-Header "Azure Platform CLI Reference"
        Write-Host "Usage: .\platform-azure.ps1 <Action> [Environment] [Options]" -ForegroundColor White
        Write-Host ""
        Write-Host "Actions:" -ForegroundColor Cyan
        Write-Host "  plan          Validate and plan the selected Azure Terraform workspace"
        Write-Host "  apply         Provision Azure infrastructure (VNet, AKS, PostgreSQL, Redis, AppGW, etc.)"
        Write-Host "  rollback      Execute emergency rollback and release the Azure state lease"
        Write-Host "  unlock        Force-release a stranded Azure Blob state lock"
        Write-Host "  status        Display Terraform state and Azure resource group health"
        Write-Host "  cost          Estimate Azure infrastructure spend with the FinOps engine"
        Write-Host ""
        Write-Host "Environments:" -ForegroundColor Cyan
        Write-Host "  dev           Burstable tier (Branch: develop | Namespace: dev)"
        Write-Host "  staging       Medium performance tier (Branch: staging | Namespace: staging)"
        Write-Host "  prod          High performance HA tier (Branch: master | Namespace: production)"
    }
}
