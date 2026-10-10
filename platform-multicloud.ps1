<#
.SYNOPSIS
    Enterprise Multi-Cloud Platform Orchestrator (AWS, Azure, GCP)
.DESCRIPTION
    Unified, non-cascading orchestrator for multi-cloud infrastructure and workloads across:
    - Providers: AWS (Amazon Web Services), Azure (Microsoft Azure), GCP (Google Cloud Platform)
    - Pre-Deploy Security & Quality Gates (Gitleaks, TFLint, Trivy, Conftest OPA, Cosign, Graphviz)
    - Terraform Multi-Flavor / Multi-Cluster Lifecycle (Plan artifact, Apply, Drift, Destroy, Unlock)
    - Workload Delivery Drivers:
        * AWS: ArgoCD GitOps reconciliation & EKS context switching
        * Azure: Direct Helm umbrella chart deployment/rollback & AKS context switching
        * GCP: Direct Helm umbrella chart deployment/rollback & GKE context switching
    - OPA Gatekeeper (Cluster Admission Controller):
        * Install controller, deploy CRD templates/constraints, audit violations, test webhook enforcement
    - Post-Deploy Dynamic Quality & DAST Gates (Smoke, Newman API contract, k6 SLA, OWASP ZAP)
    - End-to-End Pipeline: Shift-left static gates -> IaC apply -> Workload delivery -> Post-deploy testing
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet(
        "plan", "apply", "destroy", "drift", "output", "unlock",
        "pre-deploy", "post-deploy", "pipeline", "sync-argocd", "apply-workloads", "rollback", "gatekeeper",
        "doctor", "status", "tools", "help"
    )]
    [string]$Command = "help",

    [Parameter(Position = 1)]
    [ValidateSet("aws", "azure", "gcp")]
    [string]$Provider = "aws",

    [ValidateSet("dev", "staging", "prod")]
    [string]$Environment = "dev",

    [ValidateSet("eks", "ecs-fargate", "ec2-compact")]
    [string]$Flavor = "eks",

    [ValidateSet("audit", "deploy", "install", "test")]
    [string]$Action = "audit",
    [switch]$Strict,

    [string]$PlanFile = "",
    [switch]$OutPlan,
    [string[]]$Target = @(),
    [string[]]$Replace = @(),
    [string[]]$Var = @(),
    [string[]]$VarFile = @(),
    [ValidateSet("", "all", "primary", "secondary")]
    [string]$DataPlane = "",

    [int]$Revision = 0,
    [string]$TargetUrl = "",
    [string]$CosignImage = "",
    [string]$CosignKey = "",
    [switch]$GenerateGraph,

    [switch]$AutoApprove,
    [switch]$Scan,
    [string]$LockId = "",
    [switch]$Install
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# Set context variables and dot-source platform-common directly (No cascading scripts)
$Platform = $Provider
$WithoutIstio = $false
$WithIstio = $true

. (Join-Path $PSScriptRoot "platform-common.ps1")

# ------------------------------------------------------------------------------
# Provider Authentication Assertions
# ------------------------------------------------------------------------------
function Assert-ProviderIdentity {
    param([string]$TargetProvider)
    switch ($TargetProvider) {
        "aws" {
            Write-Host "Verifying AWS caller identity..." -ForegroundColor Cyan
            $identity = & aws sts get-caller-identity --output json 2>&1
            if ($LASTEXITCODE -ne 0 -or -not $identity) {
                throw "AWS authentication is unavailable. Run 'aws sso login' or configure AWS credentials."
            }
            $caller = ($identity | ConvertFrom-Json)
            Write-Host "  [OK] Authenticated as: $($caller.Arn) (Account: $($caller.Account))" -ForegroundColor Green
            return $caller
        }
        "azure" {
            Write-Host "Verifying Azure subscription identity..." -ForegroundColor Cyan
            $accountJson = & az account show --output json 2>&1
            if ($LASTEXITCODE -ne 0 -or -not $accountJson) {
                throw "Azure authentication is unavailable. Run 'az login' and select an active subscription."
            }
            $account = ($accountJson | ConvertFrom-Json)
            Write-Host "  [OK] Authenticated: $($account.user.name) (Subscription: $($account.name) - $($account.id))" -ForegroundColor Green
            return $account
        }
        "gcp" {
            Write-Host "Verifying Google Cloud identity and active project..." -ForegroundColor Cyan
            $account = (& gcloud auth list --filter=status:ACTIVE --format="value(account)" 2>&1).Trim()
            if ($LASTEXITCODE -ne 0 -or -not $account) {
                throw "Google Cloud authentication is unavailable. Run 'gcloud auth login' and select an active account."
            }
            $project = (& gcloud config get-value project 2>&1).Trim()
            if ($LASTEXITCODE -ne 0 -or -not $project -or $project -eq "(unset)") {
                throw "No Google Cloud project is selected. Configure one with 'gcloud config set project <project-id>'."
            }
            Write-Host "  [OK] Authenticated: $account (Project: $project)" -ForegroundColor Green
            return @{ Account = $account; Project = $project }
        }
    }
}

# ------------------------------------------------------------------------------
# Host Tools Audit
# ------------------------------------------------------------------------------
function Show-MultiCloudToolsAudit {
    param(
        [string]$TargetProvider,
        [switch]$InstallMissing
    )
    Write-Host "`nMulti-Cloud ($($TargetProvider.ToUpper())) & DevSecOps Host Tools Audit:" -ForegroundColor Cyan
    $providerCli = switch ($TargetProvider) {
        "aws"   { @{ Name = "aws"; Package = "Amazon.AWSCLI"; Purpose = "AWS identity & EKS CLI" } }
        "azure" { @{ Name = "az"; Package = "Microsoft.AzureCLI"; Purpose = "Azure identity & AKS CLI" } }
        "gcp"   { @{ Name = "gcloud"; Package = "Google.CloudSDK"; Purpose = "Google Cloud SDK & GKE CLI" } }
    }

    $tools = @(
        $providerCli,
        @{ Name = "terraform"; Package = "Hashicorp.Terraform"; Purpose = "IaC Lifecycle engine" },
        @{ Name = "kubectl"; Package = "Kubernetes.kubectl"; Purpose = "Kubernetes cluster management" },
        @{ Name = "helm"; Package = "Helm.Helm"; Purpose = "Package manager & manifest rendering" },
        @{ Name = "gitleaks"; Package = "Gitleaks.Gitleaks"; Purpose = "Secret leakage detection" },
        @{ Name = "tflint"; Package = "TerraformLinters.tflint"; Purpose = "Terraform linting" },
        @{ Name = "trivy"; Package = "AquaSecurity.Trivy"; Purpose = "IaC misconfig & container scanner" },
        @{ Name = "conftest"; Package = "conftest"; Purpose = "OPA Policy-as-Code engine" },
        @{ Name = "cosign"; Package = "Sigstore.Cosign"; Purpose = "Supply chain signature validator" },
        @{ Name = "dot"; Package = "Graphviz.Graphviz"; Purpose = "Graphviz dependency modeling" },
        @{ Name = "k6"; Package = "k6.k6"; Purpose = "Performance & SLA benchmarking" },
        @{ Name = "docker"; Package = "Docker.DockerDesktop"; Purpose = "OWASP ZAP / container runner" }
    )

    $report = [System.Collections.Generic.List[object]]::new()
    foreach ($t in $tools) {
        $cmd = Get-Command $t.Name -ErrorAction SilentlyContinue | Select-Object -First 1
        $status = if ($cmd) { "Available ($($cmd.Source))" } else { "Missing" }
        if (-not $cmd -and $InstallMissing) {
            Write-Host "Attempting install of $($t.Package) via WinGet..." -ForegroundColor Yellow
            & winget install --id $t.Package --exact --silent --accept-source-agreements --accept-package-agreements --disable-interactivity 2>$null
            $cmd = Get-Command $t.Name -ErrorAction SilentlyContinue | Select-Object -First 1
            $status = if ($cmd) { "Installed (Reopen terminal if needed)" } else { "Failed to install" }
        }
        $report.Add([pscustomobject]@{ Tool = $t.Name; Status = $status; Purpose = $t.Purpose })
    }
    $report | Format-Table -AutoSize | Out-Host
}

# ------------------------------------------------------------------------------
# Dispatcher
# ------------------------------------------------------------------------------
switch ($Command) {
    "help" {
        Write-Host @"
================================================================================
 🚀 MULTI-CLOUD ENTERPRISE PLATFORM CLI (platform-multicloud.ps1)
================================================================================
Usage:
  .\platform-multicloud.ps1 <command> [-Provider aws|azure|gcp] [-Environment dev|staging|prod] [options]

Providers:
  aws           : Amazon Web Services (EKS multi-cluster, ECS Fargate, EC2 Compact, ArgoCD GitOps)
  azure         : Microsoft Azure (AKS primary & secondary data planes, Helm delivery)
  gcp           : Google Cloud Platform (GKE primary & secondary data planes, Helm delivery)

Commands:
  pre-deploy    : Runs Gitleaks, TFLint, Trivy, Conftest OPA, Cosign, and Graphviz.
  plan          : Generates binary execution plan (.tfplan) with linting.
  apply         : Applies verified execution plan artifact to Cloud (with prod safeguards).
  destroy       : Destroys infrastructure with confirmation checks.
  drift         : Audits live infrastructure drift against remote state.
  output        : Displays Terraform outputs.
  unlock        : Forcibly releases stale state lock (-LockId <id>).
  sync-argocd   : Triggers ArgoCD GitOps reconciliation (AWS EKS).
  apply-workloads: Deploys Helm umbrella chart directly to AKS or GKE.
  rollback      : Rolls back Helm release on AKS or GKE (-Revision <rev>).
  gatekeeper    : Audits, deploys, tests, or installs OPA Gatekeeper (-Action audit|deploy|test|install).
  post-deploy   : Runs dynamic Smoke, Newman API contracts, k6 SLA, and OWASP ZAP DAST.
  pipeline      : Runs full end-to-end pipeline (Pre-deploy -> Apply -> Delivery -> Post-deploy).
  doctor        : Audits Cloud authentication, Kubernetes connectivity, and running workloads.
  status        : Shows Terraform workspace status and active Kubernetes workloads.
  tools         : Audits host CLI dependencies (pass -Install to attempt WinGet install).

Options:
  -Provider <aws|azure|gcp>            : Target cloud provider (default: aws)
  -Environment <dev|staging|prod>      : Target environment workspace (default: dev)
  -Flavor <eks|ecs-fargate|ec2-compact>: Choose architecture stack flavor (AWS only, default: eks)
  -DataPlane <primary|secondary|all>   : Target production cluster data plane
  -TargetUrl <url>                     : Live endpoint for post-deploy tests & OWASP ZAP
  -Scan                                : Enforce pre-deploy security scan before apply
  -GenerateGraph                       : Render architecture topology diagram with dot
  -AutoApprove                         : Bypass confirmation prompts
================================================================================
"@ -ForegroundColor Cyan
    }

    "tools" {
        Show-MultiCloudToolsAudit -TargetProvider $Provider -InstallMissing:$Install
    }

    "pre-deploy" {
        Assert-ProviderIdentity -TargetProvider $Provider | Out-Null
        Invoke-PreDeploySecurityGate -Provider $Provider -Environment $Environment -Flavor $Flavor -GenerateGraph:$GenerateGraph -CosignImage $CosignImage -CosignKey $CosignKey -FailFast
    }

    "plan" {
        Assert-ProviderIdentity -TargetProvider $Provider | Out-Null
        if ($Scan) {
            Invoke-PreDeploySecurityGate -Provider $Provider -Environment $Environment -Flavor $Flavor -FailFast
        }
        Invoke-TerraformCloudLifecycle -Provider $Provider -Action plan -Environment $Environment -Flavor $Flavor -PlanFile $PlanFile -OutPlan:$OutPlan -Target $Target -Replace $Replace -Var $Var -VarFile $VarFile -DataPlane $DataPlane
    }

    "apply" {
        Assert-ProviderIdentity -TargetProvider $Provider | Out-Null
        if ($Scan) {
            Invoke-PreDeploySecurityGate -Provider $Provider -Environment $Environment -Flavor $Flavor -FailFast
        }
        Invoke-TerraformCloudLifecycle -Provider $Provider -Action apply -Environment $Environment -Flavor $Flavor -PlanFile $PlanFile -Target $Target -Replace $Replace -Var $Var -VarFile $VarFile -DataPlane $DataPlane -AutoApprove:$AutoApprove
    }

    "destroy" {
        Assert-ProviderIdentity -TargetProvider $Provider | Out-Null
        Invoke-TerraformCloudLifecycle -Provider $Provider -Action destroy -Environment $Environment -Flavor $Flavor -Target $Target -Replace $Replace -Var $Var -VarFile $VarFile -DataPlane $DataPlane -AutoApprove:$AutoApprove
    }

    "drift" {
        Assert-ProviderIdentity -TargetProvider $Provider | Out-Null
        Invoke-TerraformCloudLifecycle -Provider $Provider -Action drift -Environment $Environment -Flavor $Flavor -Target $Target -Var $Var -VarFile $VarFile -DataPlane $DataPlane
    }

    "output" {
        Assert-ProviderIdentity -TargetProvider $Provider | Out-Null
        Invoke-TerraformCloudLifecycle -Provider $Provider -Action output -Environment $Environment -Flavor $Flavor
    }

    "unlock" {
        Assert-ProviderIdentity -TargetProvider $Provider | Out-Null
        Invoke-TerraformCloudLifecycle -Provider $Provider -Action unlock -Environment $Environment -Flavor $Flavor -LockId $LockId
    }

    "sync-argocd" {
        if ($Provider -ne "aws") {
            throw "'sync-argocd' is AWS-only (ArgoCD GitOps). Use 'apply-workloads' for Azure/GCP Helm delivery."
        }
        Assert-ProviderIdentity -TargetProvider $Provider | Out-Null
        Sync-ArgoCdWorkloads -Environment $Environment
    }

    "apply-workloads" {
        if ($Provider -eq "aws") {
            throw "'apply-workloads' is for Azure and GCP Helm delivery. AWS uses ArgoCD GitOps: run 'sync-argocd'."
        }
        Assert-ProviderIdentity -TargetProvider $Provider | Out-Null
        Invoke-HelmWorkloadDeploy -Provider $Provider -Environment $Environment
    }

    "rollback" {
        if ($Provider -eq "aws") {
            throw "AWS workloads are GitOps-managed by ArgoCD. Revert the Git revision or use 'sync-argocd'."
        }
        Assert-ProviderIdentity -TargetProvider $Provider | Out-Null
        Invoke-HelmWorkloadRollback -Environment $Environment -Revision $Revision
    }

    "gatekeeper" {
        Assert-ProviderIdentity -TargetProvider $Provider | Out-Null
        switch ($Action) {
            "install" { Install-GatekeeperAdmissionController }
            "deploy"  { Deploy-GatekeeperPolicies }
            "test"    { Test-GatekeeperEnforcement -Namespace (if ($Environment -eq "prod") { "production" } else { $Environment }) }
            default   { Invoke-GatekeeperAudit -FailOnViolations:$Strict }
        }
    }

    "post-deploy" {
        if (-not $TargetUrl) {
            throw "Post-deploy testing requires -TargetUrl <url> pointing to the live storefront or ingress."
        }
        Invoke-PostDeployDynamicGate -TargetUrl $TargetUrl -Environment $Environment
    }

    "pipeline" {
        Assert-ProviderIdentity -TargetProvider $Provider | Out-Null
        Invoke-CloudFullPipeline -Provider $Provider -Environment $Environment -Flavor $Flavor -TargetUrl $TargetUrl -AutoApprove:$AutoApprove
    }

    { $_ -in @("doctor", "status") } {
        Assert-ProviderIdentity -TargetProvider $Provider | Out-Null
        Write-Host "`nAuditing $($Provider.ToUpper()) Kubernetes & Workloads in '$Environment'..." -ForegroundColor Cyan
        Invoke-TerraformCloudLifecycle -Provider $Provider -Action output -Environment $Environment -Flavor $Flavor
        $targetNs = if ($Environment -eq "prod") { "production" } else { $Environment }
        & kubectl get nodes 2>$null
        & kubectl get pods -n $targetNs 2>$null
        Invoke-GatekeeperAudit -FailOnViolations:$Strict
    }
}
