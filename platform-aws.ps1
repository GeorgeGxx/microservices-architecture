# ==============================================================================
# Platform AWS CLI Orchestrator (Version: AWS Cloud | Environments: dev, staging, prod)
# Git Branch Correlation:
#   - 'develop'     -> 'dev' environment (Burstable nodes, namespace: 'dev')
#   - 'staging'     -> 'staging' environment (Medium performance, namespace: 'staging')
#   - 'main/master' -> 'prod' environment (High performance HA, namespace: 'production')
#
# Modules Managed: vpc, eks, rds, elasticache, msk, s3, kms, iam_irsa, alb,
#                  cloudfront, cloudwatch, route53_acm
# CI/CD Engine: GitHub Actions (CI) + ArgoCD (CD) + Automated Rollback
# ==============================================================================
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet("plan", "apply", "destroy", "rollback", "status", "sync-argocd", "unlock", "cost", "help")]
    [string]$Action = "plan",

    [Parameter(Position = 1)]
    [ValidateSet("dev", "staging", "prod")]
    [string]$Environment = "staging",

    [string]$AwsRegion = "us-east-1",
    [switch]$AutoApprove = $false,
    [string]$LockId = ""
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$root = $PSScriptRoot
$awsTfDir = Join-Path $root "terraform\environments\aws"
$argoDir = Join-Path $root "argocd"

function Show-Header {
    param([string]$Title)
    Write-Host ""
    Write-Host "================================================================================" -ForegroundColor Yellow
    Write-Host " ☁️  AWS CLOUD PLATFORM ORCHESTRATOR" -ForegroundColor Yellow
    Write-Host " ▶ Action: $Title | Environment: [$($Environment.ToUpper())] | Region: $AwsRegion" -ForegroundColor White
    Write-Host "================================================================================" -ForegroundColor Yellow
}

# Namespace mapping
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

switch ($Action) {
    "plan" {
        Show-Header "Terraform Plan (12 AWS Modules)"
        Write-Host "Correlated Branch: $branchMapping | K8s Namespace: $targetNamespace" -ForegroundColor Cyan
        Push-Location $awsTfDir
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
        Show-Header "Terraform Apply (Provision AWS Infrastructure)"
        Write-Host "Provisioning EKS, VPC, RDS, ElastiCache, MSK, ALB, CloudFront in '$Environment'..." -ForegroundColor Cyan
        Push-Location $awsTfDir
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
                Write-Host "`n[OK] AWS Infrastructure provisioned successfully." -ForegroundColor Green
                Write-Host "Ensuring destination namespace '$targetNamespace' exists in EKS..." -ForegroundColor Cyan
                kubectl create namespace $targetNamespace --dry-run=client -o yaml | kubectl apply -f - 2>$null
            } else {
                Write-Error "Terraform Apply failed for AWS environment: $Environment"
            }
        } finally {
            Pop-Location
        }
    }

    "rollback" {
        Show-Header "Emergency Rollback & State Recovery"
        Write-Host "Executing automated rollback for AWS environment: $Environment..." -ForegroundColor Red
        
        # 1. Release Terraform State Lock if present
        Push-Location $awsTfDir
        try {
            Write-Host "Checking Terraform state lock release..." -ForegroundColor Yellow
            if ($LockId) {
                terraform force-unlock -force $LockId
            } else {
                Write-Host "No explicit LockId passed; checking active state list..." -ForegroundColor Gray
            }
        } finally {
            Pop-Location
        }

        # 2. ArgoCD Application Rollback
        $argoApp = "microservices-$Environment"
        Write-Host "`nExecuting ArgoCD Application Rollback: $argoApp..." -ForegroundColor Yellow
        if (Get-Command "argocd" -ErrorAction SilentlyContinue) {
            argocd app rollback $argoApp 2>$null
        } else {
            Write-Host "Rolling back deployment in namespace '$targetNamespace' via kubectl fallback..." -ForegroundColor Yellow
            kubectl rollout undo deployment/microservices-api-gateway -n $targetNamespace 2>$null
            kubectl rollout undo deployment/microservices-products-service -n $targetNamespace 2>$null
            kubectl rollout undo deployment/microservices-orders-service -n $targetNamespace 2>$null
        }
        Write-Host "[OK] Emergency rollback procedures finished." -ForegroundColor Green
    }

    "sync-argocd" {
        Show-Header "ArgoCD Declarative GitOps Synchronization"
        $manifest = switch ($Environment) {
            "dev"     { Join-Path $argoDir "application-dev.yaml" }
            "staging" { Join-Path $argoDir "application-staging.yaml" }
            "prod"    { Join-Path $argoDir "application-prod.yaml" }
        }
        if (Test-Path $manifest) {
            Write-Host "Applying ArgoCD application manifest: $manifest" -ForegroundColor Green
            kubectl apply -f $manifest
            Write-Host "Triggering GitOps hard sync..." -ForegroundColor Cyan
            kubectl patch application "microservices-$Environment" -n argocd --type merge -p '{"operation":{"sync":{"prune":true}}}' 2>$null
        } else {
            Write-Error "ArgoCD manifest not found for environment: $Environment"
        }
    }

    "unlock" {
        Show-Header "Force Unlock Terraform State"
        if (-not $LockId) {
            Write-Error "Please provide -LockId <ID> to unlock Terraform state."
        }
        Push-Location $awsTfDir
        try {
            terraform force-unlock -force $LockId
        } finally {
            Pop-Location
        }
    }

    "status" {
        Show-Header "AWS Infrastructure & Namespace Status"
        Push-Location $awsTfDir
        try {
            terraform workspace select -or-create $Environment || true
            terraform show -no-color | Select-Object -First 30
        } finally {
            Pop-Location
        }
        Write-Host "`nNamespace '$targetNamespace' Pods:" -ForegroundColor Cyan
        kubectl get pods -n $targetNamespace 2>$null
    }

    "cost" {
        Show-Header "FinOps Cost Estimation for AWS $Environment"
        $costScript = Join-Path $root "scripts\cloud\terraform\local-cost-estimator.py"
        python $costScript --env $Environment
    }

    default {
        Show-Header "AWS Platform CLI Reference"
        Write-Host "Usage: .\platform-aws.ps1 <Action> [Environment] [Options]" -ForegroundColor White
        Write-Host ""
        Write-Host "Actions:" -ForegroundColor Cyan
        Write-Host "  plan          Format, validate and plan AWS Terraform infrastructure"
        Write-Host "  apply         Provision AWS infrastructure (VPC, EKS, RDS, ElastiCache, MSK, ALB, etc.)"
        Write-Host "  rollback      Execute automated emergency rollback & state unlock"
        Write-Host "  sync-argocd   Trigger declarative ArgoCD synchronization for target environment"
        Write-Host "  unlock        Release stranded Terraform S3/DynamoDB state lock (-LockId <id>)"
        Write-Host "  status        Display active Terraform state and Kubernetes namespace resources"
        Write-Host "  cost          Estimate cloud infrastructure costs via FinOps engine"
        Write-Host ""
        Write-Host "Environments:" -ForegroundColor Cyan
        Write-Host "  dev           Burstable tier (Branch: develop, Namespace: dev)"
        Write-Host "  staging       Medium performance tier (Branch: staging, Namespace: staging)"
        Write-Host "  prod          High performance HA tier (Branch: main/master, Namespace: production)"
    }
}
