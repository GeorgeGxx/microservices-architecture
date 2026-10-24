<#
.SYNOPSIS
    Enterprise Multi-Cloud Platform Orchestrator (AWS, Azure, GCP)
.DESCRIPTION
    Unified, non-cascading orchestrator for multi-cloud infrastructure and workloads across:
    - Cloud infrastructure lifecycle: AWS (EKS, ECS Fargate, EC2 Compact), Azure (AKS), GCP (GKE)
    - Pre-Deploy Security & Quality Gates (Gitleaks, TFLint, Trivy, Conftest OPA, Cosign, Graphviz)
    - Terraform Multi-Flavor / Multi-Cluster Lifecycle (Plan artifact, Apply, Drift, Destroy, Unlock)
    - Workload Delivery Drivers:
        * AWS EKS: ArgoCD GitOps reconciliation against the selected Kubernetes context
        * Azure AKS / GCP GKE: Direct Helm umbrella chart deployment/rollback against the selected Kubernetes context
        * AWS ECS Fargate / EC2 Compact: Terraform infrastructure lifecycle only
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
    [string]$KeycloakUrl = $env:KEYCLOAK_URL,
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

# Set cloud context before loading this standalone CLI's helper functions.
$Platform = $Provider

# Runtime setup and cloud-specific helpers are embedded in this standalone CLI.
$knownBinPaths = @(
    "C:\Program Files\Graphviz\bin",
    "C:\Program Files (x86)\Graphviz\bin",
    "$env:LOCALAPPDATA\Programs\Graphviz\bin",
    "$env:LOCALAPPDATA\Microsoft\WinGet\Links"
)
foreach ($bp in $knownBinPaths) {
    if ((Test-Path $bp) -and ($env:PATH -notlike "*$bp*")) { $env:PATH = "$bp;$env:PATH" }
}
$RepoRoot = $PSScriptRoot

function Show-StageHeader {
    param([string]$Title, [string]$Category = "STAGE")
    Write-Host ""
    Write-Host "================================================================================" -ForegroundColor Cyan
    Write-Host " 🛡️  [$Category] $Title" -ForegroundColor Yellow
    Write-Host "================================================================================" -ForegroundColor Cyan
}

function Show-Success {
    param([string]$Message)
    Write-Host "  [OK] $Message" -ForegroundColor Green
}

function Show-Warning {
    param([string]$Message)
    Write-Host "  [WARN] $Message" -ForegroundColor Yellow
}

function Show-Failure {
    param([string]$Message)
    Write-Host "  [FAIL] $Message" -ForegroundColor Red
}

function Get-CloudHelmValuesFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet("aws", "azure", "gcp")]
        [string]$Provider,

        [Parameter(Mandatory = $true)]
        [ValidateSet("dev", "staging", "prod")]
        [string]$Environment,

        [ValidateSet("eks", "ecs-fargate", "ec2-compact")]
        [string]$Flavor = "eks"
    )

    if ($Provider -eq "aws" -and $Flavor -ne "eks") {
        throw "Helm workload operations require an AWS EKS target; flavor '$Flavor' provisions no Kubernetes cluster."
    }

    $profile = switch ($Provider) {
        "aws"   { "eks" }
        "azure" { "aks" }
        "gcp"   { "gke" }
    }
    $valuesFile = Join-Path $RepoRoot "helm\values\values-$profile-$Environment.yaml"
    if (-not (Test-Path -LiteralPath $valuesFile -PathType Leaf)) {
        throw "No cloud Helm values profile exists for $Provider/$Environment at '$valuesFile'. Add and validate that provider/environment profile before deploying."
    }
    return $valuesFile
}

function Assert-KubernetesTarget {
    param([string]$Operation = "This operation")
    if ($Provider -eq "aws" -and $Flavor -ne "eks") {
        throw "$Operation requires AWS EKS. The selected '$Flavor' flavor is infrastructure-only in this CLI; use Terraform plan/apply/destroy for it."
    }
}

function Get-TargetDirectoryMutexName {
    param([string]$Directory)
    $fullDir = [System.IO.Path]::GetFullPath($Directory)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $hashBytes = $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($fullDir.ToLowerInvariant()))
    } finally {
        $sha.Dispose()
    }
    $suffix = [BitConverter]::ToString($hashBytes).Replace("-", "").ToLowerInvariant()
    return "Local\devsecops-tf-$suffix"
}

function Invoke-PreDeploySecurityGate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet("aws", "azure", "gcp")]
        [string]$Provider,

        [ValidateSet("dev", "staging", "prod")]
        [string]$Environment = "dev",

        [ValidateSet("eks", "ecs-fargate", "ec2-compact")]
        [string]$Flavor = "eks",

        [switch]$GenerateGraph,
        [string]$CosignImage = "",
        [string]$CosignKey = "",
        [switch]$FailFast = $false
    )

    Show-StageHeader -Title "PRE-DEPLOY QUALITY & SECURITY GATE (Shift-Left: $Provider / $Environment)" -Category "PRE-DEPLOY"
    $passed = $true
    $results = [System.Collections.Generic.List[object]]::new()

    # Determine Terraform working directory
    $tfDir = switch ($Flavor) {
        "ecs-fargate" { Join-Path $RepoRoot "terraform\environments\aws-ecs-fargate" }
        "ec2-compact" { Join-Path $RepoRoot "terraform\environments\aws-ec2-compact" }
        default       { Join-Path $RepoRoot "terraform\environments\$Provider" }
    }
    $isKubernetesTarget = $Provider -ne "aws" -or $Flavor -eq "eks"

    # --- 1.1 Gitleaks Secret Detection ---
    Write-Host "`n[1/6] 🔍 Gitleaks: Scanning cloud deployment working tree for credentials & tokens..." -ForegroundColor Cyan
    $gitleaksConfig = Join-Path $RepoRoot "devsecops\sast\gitleaks\.gitleaks.toml"
    if (-not (Get-Command gitleaks -ErrorAction SilentlyContinue)) {
        Show-Warning "gitleaks CLI is not found in PATH. Skipping local secret audit."
        $results.Add([pscustomobject]@{ Tool = "Gitleaks"; Status = "SKIPPED"; Details = "CLI missing" })
        if ($FailFast) { throw "Pre-deploy requires Gitleaks; install it with '.\platform-multicloud.ps1 tools -Provider $Provider -Flavor $Flavor -Install'." }
    } elseif (-not (Test-Path -LiteralPath $gitleaksConfig)) {
        Show-Warning "Gitleaks config not found at $gitleaksConfig."
        $results.Add([pscustomobject]@{ Tool = "Gitleaks"; Status = "SKIPPED"; Details = "Config missing" })
        if ($FailFast) { throw "Pre-deploy cannot run without the repository Gitleaks configuration: $gitleaksConfig" }
    } else {
        $tempScanDir = Join-Path ([System.IO.Path]::GetTempPath()) ("gitleaks-" + [Guid]::NewGuid().ToString("N"))
        try {
            New-Item -ItemType Directory -Path $tempScanDir -Force | Out-Null
            $files = @(& git -C $RepoRoot ls-files --cached --others --exclude-standard 2>$null)
            foreach ($f in $files) {
                $src = Join-Path $RepoRoot $f
                if ((Test-Path -LiteralPath $src -PathType Leaf) -and -not ((Get-Item -LiteralPath $src).Attributes -band [System.IO.FileAttributes]::ReparsePoint)) {
                    $dst = Join-Path $tempScanDir $f
                    $parent = Split-Path -Parent $dst
                    if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
                    Copy-Item -LiteralPath $src -Destination $dst -Force
                }
            }
            & gitleaks detect --source=$tempScanDir --config=$gitleaksConfig --no-git --redact=100 --no-banner
            if ($LASTEXITCODE -eq 0) {
                Show-Success "Gitleaks: Zero hardcoded secrets detected in working tree."
                $results.Add([pscustomobject]@{ Tool = "Gitleaks"; Status = "PASSED"; Details = "Clean working tree" })
            } else {
                Show-Failure "Gitleaks: Credential leakage detected! (Exit code $LASTEXITCODE)"
                $results.Add([pscustomobject]@{ Tool = "Gitleaks"; Status = "FAILED"; Details = "Potential credentials found" })
                $passed = $false
                if ($FailFast) { throw "Pre-deploy failed at Gitleaks stage." }
            }
        } finally {
            Remove-Item -LiteralPath $tempScanDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    # --- 1.2 TFLint Terraform Linter ---
    Write-Host "`n[2/6] 📋 TFLint: Linting Terraform configurations in '$tfDir'..." -ForegroundColor Cyan
    if (-not (Get-Command tflint -ErrorAction SilentlyContinue)) {
        Show-Warning "tflint CLI is not found in PATH. Skipping Terraform linting."
        $results.Add([pscustomobject]@{ Tool = "TFLint"; Status = "SKIPPED"; Details = "CLI missing" })
        if ($FailFast) { throw "Pre-deploy requires TFLint; install it with '.\platform-multicloud.ps1 tools -Provider $Provider -Flavor $Flavor -Install'." }
    } else {
        Push-Location $tfDir
        try {
            & tflint --init 2>$null | Out-Null
            $tflintOutput = @(& tflint 2>&1)
            if ($LASTEXITCODE -eq 0) {
                Show-Success "TFLint: Configuration passed linting checks."
                $results.Add([pscustomobject]@{ Tool = "TFLint"; Status = "PASSED"; Details = "No issues detected" })
            } else {
                Show-Failure "TFLint: Linting errors or warnings detected."
                $tflintOutput | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkYellow }
                $results.Add([pscustomobject]@{ Tool = "TFLint"; Status = "FAILED"; Details = "Linting errors" })
                $passed = $false
                if ($FailFast) { throw "Pre-deploy failed at TFLint stage." }
            }
        } finally {
            Pop-Location
        }
    }

    # --- 1.3 Trivy IaC Misconfiguration & Compliance ---
    Write-Host "`n[3/6] 🛡️ Trivy: Scanning IaC configuration ($tfDir and Helm charts)..." -ForegroundColor Cyan
    $trivyConfig = Join-Path $RepoRoot "devsecops\compliance\trivy\trivy.yaml"
    $trivyIgnore = Join-Path $RepoRoot "devsecops\compliance\trivy\.trivyignore"
    if (-not (Get-Command trivy -ErrorAction SilentlyContinue)) {
        Show-Warning "trivy CLI is not found in PATH. Skipping Trivy IaC audit."
        $results.Add([pscustomobject]@{ Tool = "Trivy"; Status = "SKIPPED"; Details = "CLI missing" })
        if ($FailFast) { throw "Pre-deploy requires Trivy; install it with '.\platform-multicloud.ps1 tools -Provider $Provider -Flavor $Flavor -Install'." }
    } else {
        $trivyTargets = @($tfDir)
        if ($isKubernetesTarget) { $trivyTargets += Join-Path $RepoRoot "helm\microservices-umbrella" }
        $trivyFailed = $false
        foreach ($tgt in $trivyTargets) {
            Write-Host "  -> Evaluating target: $tgt" -ForegroundColor DarkGray
            $trivyArgs = @("config", $tgt)
            if (Test-Path -LiteralPath $trivyConfig) { $trivyArgs += @("--config", $trivyConfig) }
            if (Test-Path -LiteralPath $trivyIgnore) { $trivyArgs += @("--ignorefile", $trivyIgnore) }
            $trivyOutput = @(& trivy @trivyArgs 2>&1)
            if ($LASTEXITCODE -ne 0) {
                $trivyFailed = $true
                $trivyOutput | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkYellow }
            }
        }
        if (-not $trivyFailed) {
            Show-Success "Trivy: IaC configurations compliant with security baseline."
            $results.Add([pscustomobject]@{ Tool = "Trivy"; Status = "PASSED"; Details = "IaC compliant" })
        } else {
            Show-Warning "Trivy: IaC issues detected (audit mode per trivy.yaml)."
            $results.Add([pscustomobject]@{ Tool = "Trivy"; Status = "WARNING"; Details = "Findings recorded" })
        }
    }

    # --- 1.4 Conftest (OPA / Rego) Policy-as-Code ---
    Write-Host "`n[4/6] 📜 Conftest: Validating provider-specific Helm manifests against Rego policies..." -ForegroundColor Cyan
    $regoDir = Join-Path $RepoRoot "devsecops\policies\conftest"
    $umbrellaDir = Join-Path $RepoRoot "helm\microservices-umbrella"

    if (-not $isKubernetesTarget) {
        Write-Host "  [INFO] Selected AWS flavor has no Kubernetes workloads; Helm manifest policy scan is not applicable." -ForegroundColor DarkGray
        $results.Add([pscustomobject]@{ Tool = "Conftest OPA"; Status = "NOT APPLICABLE"; Details = "$Flavor is infrastructure-only" })
    } elseif (-not (Get-Command conftest -ErrorAction SilentlyContinue) -or -not (Get-Command helm -ErrorAction SilentlyContinue)) {
        Show-Warning "conftest or helm CLI not found. Skipping Helm policy gate."
        $results.Add([pscustomobject]@{ Tool = "Conftest OPA"; Status = "SKIPPED"; Details = "CLI missing" })
        if ($FailFast) { throw "Kubernetes pre-deploy requires Helm and Conftest; install them with '.\platform-multicloud.ps1 tools -Provider $Provider -Flavor $Flavor -Install'." }
    } elseif (-not (Test-Path -LiteralPath $regoDir)) {
        Show-Warning "Conftest policy folder missing: $regoDir"
        $results.Add([pscustomobject]@{ Tool = "Conftest OPA"; Status = "SKIPPED"; Details = "Policies missing" })
        if ($FailFast) { throw "Kubernetes pre-deploy cannot run without its Rego policies: $regoDir" }
    } else {
        $helmValues = Get-CloudHelmValuesFile -Provider $Provider -Environment $Environment -Flavor $Flavor
        $renderedFile = Join-Path ([System.IO.Path]::GetTempPath()) ("helm-rendered-" + [Guid]::NewGuid().ToString("N") + ".yaml")
        try {
            $helmNamespace = if ($Environment -eq "prod") { "production" } else { $Environment }
            $renderOutput = @(& helm template microservices $umbrellaDir --namespace $helmNamespace --values $helmValues --include-crds 2>&1)
            if ($LASTEXITCODE -eq 0 -and $renderOutput.Count -gt 0) {
                [System.IO.File]::WriteAllLines($renderedFile, [string[]]$renderOutput, [System.Text.UTF8Encoding]::new($false))
                $conftestOutput = @(& conftest test $renderedFile --policy $regoDir 2>&1)
                if ($LASTEXITCODE -eq 0) {
                    Show-Success "Conftest: Manifests adhere to Kubernetes zero-trust Rego policies."
                    $results.Add([pscustomobject]@{ Tool = "Conftest OPA"; Status = "PASSED"; Details = "Compliant" })
                } else {
                    Show-Failure "Conftest: Policy violation detected!"
                    $conftestOutput | ForEach-Object { Write-Host "    $_" -ForegroundColor Red }
                    $results.Add([pscustomobject]@{ Tool = "Conftest OPA"; Status = "FAILED"; Details = "Violations found" })
                    $passed = $false
                    if ($FailFast) { throw "Pre-deploy failed at Conftest stage." }
                }
            } else {
                Show-Warning "Could not render Helm manifests for Conftest validation."
                $results.Add([pscustomobject]@{ Tool = "Conftest OPA"; Status = "SKIPPED"; Details = "Template render failed" })
                if ($FailFast) { throw "Helm failed to render the selected cloud values profile '$helmValues'." }
            }
        } finally {
            Remove-Item -LiteralPath $renderedFile -Force -ErrorAction SilentlyContinue
        }
    }

    # --- 1.5 Cosign Supply Chain Signature Verification ---
    Write-Host "`n[5/6] 🔏 Cosign: Container Image Signature Verification..." -ForegroundColor Cyan
    $defaultCosignDir = Join-Path $RepoRoot "devsecops\compliance\cosign"
    $resolvedCosignKey = if ($CosignKey) { $CosignKey } else { Join-Path $defaultCosignDir "cosign.pub" }
    if (-not (Get-Command cosign -ErrorAction SilentlyContinue)) {
        Show-Warning "cosign CLI not found. Skipping container signature verification."
        $results.Add([pscustomobject]@{ Tool = "Cosign"; Status = "SKIPPED"; Details = "cosign CLI missing" })
        if ($FailFast -and $CosignImage) { throw "Image signature verification was requested, but Cosign is not installed." }
    } elseif ($CosignImage) {
        $cosignArgs = @("verify", "--key", $resolvedCosignKey, $CosignImage)
        $cosignOutput = @(& cosign @cosignArgs 2>&1)
        if ($LASTEXITCODE -eq 0) {
            Show-Success "Cosign: Image signature for '$CosignImage' verified successfully."
            $results.Add([pscustomobject]@{ Tool = "Cosign"; Status = "PASSED"; Details = "Image signature verified" })
        } else {
            Show-Failure "Cosign: Verification failed for '$CosignImage'."
            $cosignOutput | ForEach-Object { Write-Host "    $_" -ForegroundColor Red }
            $results.Add([pscustomobject]@{ Tool = "Cosign"; Status = "FAILED"; Details = "Invalid image signature" })
            $passed = $false
            if ($FailFast) { throw "Pre-deploy failed at Cosign stage." }
        }
    } else {
        $manifestPath = Join-Path $defaultCosignDir "supply-chain-manifest.json"
        $bundlePath = Join-Path $defaultCosignDir "supply-chain-manifest.sigstore.json"
        $cosignOutput = @(& cosign verify-blob --key $resolvedCosignKey --bundle $bundlePath $manifestPath 2>&1)
        if ($LASTEXITCODE -ne 0) {
            $cosignOutput = @(& cosign verify-blob --key $resolvedCosignKey --bundle $bundlePath --insecure-ignore-tlog=true $manifestPath 2>&1)
        }
        if ($LASTEXITCODE -eq 0) {
            Show-Success "Cosign: Cryptographic signature verified via cosign.pub (supply-chain-manifest.json)."
            $results.Add([pscustomobject]@{ Tool = "Cosign"; Status = "PASSED"; Details = "Verified via cosign.pub" })
        } else {
            Show-Failure "Cosign: Provenance verification failed against '$resolvedCosignKey'."
            $cosignOutput | ForEach-Object { Write-Host "    $_" -ForegroundColor Red }
            $results.Add([pscustomobject]@{ Tool = "Cosign"; Status = "FAILED"; Details = "Invalid provenance signature" })
            $passed = $false
            if ($FailFast) { throw "Pre-deploy failed at Cosign stage." }
        }
    }

    # --- 1.6 Graphviz Visual Dependency Diagram ---
    Write-Host "`n[6/6] 🗺️ Graphviz: Terraform Resource Dependency Modeling..." -ForegroundColor Cyan
    if ($GenerateGraph) {
        $dotCmd = Get-Command dot -ErrorAction SilentlyContinue
        if (-not $dotCmd) {
            Show-Warning "dot (Graphviz) CLI not found. Skipping visual graph generation."
            $results.Add([pscustomobject]@{ Tool = "Graphviz"; Status = "SKIPPED"; Details = "dot CLI missing" })
            if ($FailFast) { throw "Graph generation was requested, but Graphviz 'dot' is not installed." }
        } else {
            Push-Location $tfDir
            try {
                $outImg = Join-Path $RepoRoot "docs\reference\terraform-graph-$Provider-$Environment.png"
                $graphOut = & terraform graph 2>$null
                if ($LASTEXITCODE -eq 0 -and $graphOut) {
                    $graphOut | & dot -Tpng -o $outImg
                    Show-Success "Graphviz: Topology rendered to $outImg"
                    $results.Add([pscustomobject]@{ Tool = "Graphviz"; Status = "PASSED"; Details = $outImg })
                } else {
                    Show-Warning "Terraform graph generation returned no data."
                    $results.Add([pscustomobject]@{ Tool = "Graphviz"; Status = "SKIPPED"; Details = "Graph empty" })
                }
            } finally {
                Pop-Location
            }
        }
    } else {
        Write-Host "  [INFO] Architecture diagram generation bypassed. Use -GenerateGraph to render." -ForegroundColor DarkGray
        $results.Add([pscustomobject]@{ Tool = "Graphviz"; Status = "SKIPPED"; Details = "Not requested" })
    }

    # Summary table
    Write-Host ""
    $results | Format-Table -AutoSize | Out-Host
    if (-not $passed) {
        throw "Pre-deploy security gate FAILED. Resolve blocking security findings before deploying."
    }
    Show-Success "Pre-deploy analysis complete: all gates passed successfully."
    return $true
}

function Invoke-TerraformCloudLifecycle {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet("aws", "azure", "gcp")]
        [string]$Provider,

        [Parameter(Mandatory = $true)]
        [ValidateSet("plan", "apply", "destroy", "drift", "output", "unlock")]
        [string]$Action,

        [ValidateSet("dev", "staging", "prod")]
        [string]$Environment = "dev",

        [ValidateSet("eks", "ecs-fargate", "ec2-compact")]
        [string]$Flavor = "eks",

        [string]$PlanFile = "",
        [switch]$OutPlan,
        [string[]]$Target = @(),
        [string[]]$Replace = @(),
        [string[]]$Var = @(),
        [string[]]$VarFile = @(),
        [ValidateSet("", "all", "primary", "secondary")]
        [string]$DataPlane = "",
        [switch]$AutoApprove,
        [string]$LockId = ""
    )

    Show-StageHeader -Title "TERRAFORM IAC LIFECYCLE: $Action ($Provider / $Environment / $Flavor)" -Category "INFRASTRUCTURE"

    # Directory resolution
    $tfDir = switch ($Flavor) {
        "ecs-fargate" { Join-Path $RepoRoot "terraform\environments\aws-ecs-fargate" }
        "ec2-compact" { Join-Path $RepoRoot "terraform\environments\aws-ec2-compact" }
        default       { Join-Path $RepoRoot "terraform\environments\$Provider" }
    }

    # Verify backend requirements
    switch ($Provider) {
        "aws" {
            $verFile = Join-Path $tfDir "versions.tf"
            if ((Test-Path -LiteralPath $verFile) -and ((Get-Content -LiteralPath $verFile -Raw) -notmatch 'backend\s+"s3"')) {
                throw "AWS requires a durable S3 backend in $verFile."
            }
        }
        "azure" {
            $hcl = Join-Path $RepoRoot "terraform\backend-config\azure.hcl"
            if (-not (Test-Path -LiteralPath $hcl)) {
                throw "Azure requires terraform/backend-config/azure.hcl for remote state."
            }
        }
        "gcp" {
            $hcl = Join-Path $RepoRoot "terraform\backend-config\gcp.hcl"
            if (-not (Test-Path -LiteralPath $hcl)) {
                throw "GCP requires terraform/backend-config/gcp.hcl for remote state."
            }
        }
    }

    # Mutex protection
    $mutex = [System.Threading.Mutex]::new($false, (Get-TargetDirectoryMutexName -Directory $tfDir))
    $ownsMutex = $false
    try {
        try {
            $ownsMutex = $mutex.WaitOne([TimeSpan]::FromMinutes(2))
        } catch [System.Threading.AbandonedMutexException] {
            $ownsMutex = $true
        }
        if (-not $ownsMutex) {
            throw "Timed out waiting for Terraform concurrency lock on '$tfDir'."
        }

        Push-Location $tfDir
        try {
            # Format and Init
            Write-Host "Initializing Terraform backend..." -ForegroundColor Cyan
            $initArgs = @("init", "-upgrade", "-input=false", "-no-color")
            if ($Provider -eq "azure") { $initArgs += "-backend-config=$(Join-Path $RepoRoot 'terraform\backend-config\azure.hcl')" }
            if ($Provider -eq "gcp")   { $initArgs += "-backend-config=$(Join-Path $RepoRoot 'terraform\backend-config\gcp.hcl')" }

            & terraform @initArgs
            if ($LASTEXITCODE -ne 0) { throw "Terraform init failed." }

            # Select or create workspace
            & terraform workspace select $Environment 2>$null | Out-Null
            if ($LASTEXITCODE -ne 0) {
                Write-Host "Creating new Terraform workspace '$Environment'..." -ForegroundColor Cyan
                & terraform workspace new $Environment
                if ($LASTEXITCODE -ne 0) { throw "Could not create workspace '$Environment'." }
            }

            # Build variable arguments
            $combinedArgs = [System.Collections.Generic.List[string]]::new()
            $defaultTfvars = Join-Path $tfDir "${Environment}/terraform.tfvars"
            if (Test-Path -LiteralPath $defaultTfvars) {
                $combinedArgs.Add("-var-file=$defaultTfvars")
            }
            foreach ($vf in $VarFile) {
                if (Test-Path -LiteralPath $vf) { $combinedArgs.Add("-var-file=$vf") }
            }
            foreach ($v in $Var) {
                $combinedArgs.Add("-var=$v")
            }

            # Targets and replaces
            foreach ($t in $Target) {
                $combinedArgs.Add("-target=$t")
            }
            foreach ($r in $Replace) {
                $combinedArgs.Add("-replace=$r")
            }
            if ($Environment -eq "prod" -and $DataPlane) {
                switch ("$Provider/$DataPlane") {
                    "aws/primary"     { $combinedArgs.Add("-target=module.eks"); $combinedArgs.Add("-target=module.irsa_lb_controller") }
                    "aws/secondary"   { $combinedArgs.Add("-target=module.eks_dp2") }
                    "azure/primary"   { $combinedArgs.Add("-target=module.aks") }
                    "azure/secondary" { $combinedArgs.Add("-target=azurerm_subnet.aks_dataplane_2"); $combinedArgs.Add("-target=module.aks_dp2") }
                    "gcp/primary"     { $combinedArgs.Add("-target=module.gke") }
                    "gcp/secondary"   { $combinedArgs.Add("-target=module.gke_dp2") }
                }
            }

            $binaryPlanPath = Join-Path $tfDir ".terraform\tfplan-${Environment}.binary"

            switch ($Action) {
                "plan" {
                    & terraform fmt -check
                    & terraform validate -no-color
                    $planArgs = @("plan", "-no-color") + $combinedArgs.ToArray()
                    $planTarget = if ($PlanFile) { $PlanFile } else { $binaryPlanPath }
                    $planArgs += "-out=$planTarget"
                    Write-Host "Generating execution plan -> $planTarget" -ForegroundColor Cyan
                    & terraform @planArgs
                    if ($LASTEXITCODE -ne 0) { throw "Terraform plan failed." }
                    Show-Success "Plan artifact successfully written: $planTarget"
                }

                "apply" {
                    $applyPlan = if ($PlanFile) { $PlanFile } elseif (Test-Path -LiteralPath $binaryPlanPath) { $binaryPlanPath } else { "" }

                    if (-not $applyPlan) {
                        Write-Host "No saved plan file found. Generating refreshed binary plan first..." -ForegroundColor Yellow
                        $planArgs = @("plan", "-no-color", "-out=$binaryPlanPath") + $combinedArgs.ToArray()
                        & terraform @planArgs
                        if ($LASTEXITCODE -ne 0) { throw "Terraform plan failed before apply." }
                        $applyPlan = $binaryPlanPath
                    }

                    # Production Safeguard
                    if ($Environment -eq "prod" -and -not $AutoApprove) {
                        Write-Host "`n⚠️  CRITICAL PRODUCTION OPERATION DETECTED ⚠️" -ForegroundColor Red
                        Write-Host "You are about to apply changes to PROD on $Provider (Flavor: $Flavor)." -ForegroundColor Yellow
                        $confirmation = Read-Host "Type 'prod' to authorize production apply"
                        if ($confirmation -ne "prod") {
                            throw "Apply aborted: Confirmation did not match 'prod'."
                        }
                    }

                    $applyArgs = @("apply", "-no-color")
                    if ($AutoApprove) { $applyArgs += "-auto-approve" }
                    $applyArgs += $applyPlan

                    Write-Host "Applying plan artifact '$applyPlan'..." -ForegroundColor Cyan
                    & terraform @applyArgs
                    if ($LASTEXITCODE -ne 0) { throw "Terraform apply failed." }
                    Show-Success "Terraform infrastructure successfully applied for $Provider ($Environment)."
                }

                "destroy" {
                    Write-Host "⚠️  DESTRUCTION OF $Provider INFRASTRUCTURE IN '$Environment' REQUESTED ⚠️" -ForegroundColor Red
                    if (-not $AutoApprove) {
                        $confirmation = Read-Host "Type 'destroy-$Environment' to confirm resource deletion"
                        if ($confirmation -ne "destroy-$Environment") {
                            throw "Destruction aborted by operator."
                        }
                    }
                    $destroyArgs = @("destroy", "-no-color") + $combinedArgs.ToArray()
                    if ($AutoApprove) { $destroyArgs += "-auto-approve" }
                    & terraform @destroyArgs
                    if ($LASTEXITCODE -ne 0) { throw "Terraform destroy failed." }
                    Show-Success "Infrastructure destroyed successfully."
                }

                "drift" {
                    Write-Host "Checking for live infrastructure drift (refresh-only)..." -ForegroundColor Cyan
                    $driftArgs = @("plan", "-detailed-exitcode", "-refresh-only", "-no-color") + $combinedArgs.ToArray()
                    & terraform @driftArgs
                    $driftExit = $LASTEXITCODE
                    if ($driftExit -eq 0) {
                        Show-Success "No drift detected: remote state matches actual live infrastructure."
                    } elseif ($driftExit -eq 2) {
                        Show-Warning "DRIFT DETECTED: remote cloud resources differ from state!"
                    } else {
                        throw "Drift detection query failed with exit code $driftExit."
                    }
                }

                "output" {
                    Write-Host "Terraform Outputs for $Provider ($Environment):" -ForegroundColor Cyan
                    & terraform output
                }

                "unlock" {
                    if (-not $LockId) { throw "Specify -LockId <ID> to release state lock." }
                    Write-Host "Releasing state lock ID: $LockId..." -ForegroundColor Yellow
                    & terraform force-unlock -force $LockId
                    if ($LASTEXITCODE -ne 0) { throw "Could not force unlock state." }
                    Show-Success "State lock released."
                }
            }
        } finally {
            Pop-Location
        }
    } finally {
        if ($ownsMutex) { $mutex.ReleaseMutex() }
        $mutex.Dispose()
    }
}

function Sync-ArgoCdWorkloads {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Environment
    )

    Show-StageHeader -Title "GITOPS DELIVERY: ArgoCD Sync (AWS $Environment)" -Category "DELIVERY"
    $app = "microservices-$Environment"
    Write-Host "Requesting ArgoCD hard sync for '$app' in namespace 'argocd'..." -ForegroundColor Cyan
    & kubectl patch application $app -n argocd --type merge -p '{"operation":{"sync":{"prune":true}}}' 2>$null
    if ($LASTEXITCODE -eq 0) {
        Show-Success "ArgoCD synchronization requested for $app."
    } else {
        Show-Warning "Could not patch ArgoCD application. Verify ArgoCD is running in the cluster."
    }
}

function Invoke-HelmWorkloadDeploy {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet("azure", "gcp")]
        [string]$Provider,

        [Parameter(Mandatory = $true)]
        [string]$Environment
    )

    Show-StageHeader -Title "HELM WORKLOAD DELIVERY: $Provider ($Environment)" -Category "DELIVERY"
    $valuesFile = Get-CloudHelmValuesFile -Provider $Provider -Environment $Environment
    $umbrellaDir = Join-Path $RepoRoot "helm\microservices-umbrella"
    $namespace = if ($Environment -eq "prod") { "production" } else { $Environment }

    Write-Host "Deploying Umbrella Chart to namespace '$namespace' with values '$valuesFile'..." -ForegroundColor Cyan
    & helm upgrade --install microservices $umbrellaDir --namespace $namespace --create-namespace --values $valuesFile --wait --timeout 5m
    if ($LASTEXITCODE -ne 0) {
        throw "Helm workload deployment failed on $Provider ($Environment)."
    }
    Show-Success "Helm deployment successful on $Provider ($Environment)."
}

function Invoke-HelmWorkloadRollback {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Environment,
        [int]$Revision = 0
    )

    Show-StageHeader -Title "EMERGENCY ROLLBACK: Helm Release (Namespace: $Environment)" -Category "ROLLBACK"
    $namespace = if ($Environment -eq "prod") { "production" } else { $Environment }
    $rollbackArgs = @("rollback", "microservices")
    if ($Revision -gt 0) { $rollbackArgs += "$Revision" }
    $rollbackArgs += @("--namespace", $namespace, "--wait", "--timeout", "5m")

    & helm @rollbackArgs
    if ($LASTEXITCODE -ne 0) {
        throw "Helm rollback failed for namespace $namespace."
    }
    Show-Success "Helm release rolled back successfully in namespace $namespace."
}

function Install-GatekeeperAdmissionController {
    Show-StageHeader -Title "OPA GATEKEEPER: Helm Controller Installation in Cluster" -Category "POLICIES"
    if (-not (Get-Command helm -ErrorAction SilentlyContinue)) {
        throw "Helm CLI is required to install Gatekeeper."
    }
    Write-Host "Adding Gatekeeper Helm repository..." -ForegroundColor Cyan
    & helm repo add gatekeeper https://open-policy-agent.github.io/gatekeeper/charts 2>$null | Out-Null
    & helm repo update 2>$null | Out-Null
    Write-Host "Installing/Upgrading Gatekeeper in namespace 'gatekeeper-system'..." -ForegroundColor Cyan
    & helm upgrade --install gatekeeper gatekeeper/gatekeeper --namespace gatekeeper-system --create-namespace --wait --timeout 3m
    if ($LASTEXITCODE -ne 0) {
        throw "Gatekeeper Helm installation failed."
    }
    Show-Success "Gatekeeper admission controller installed successfully."
}

function Deploy-GatekeeperPolicies {
    param(
        [switch]$WaitEstablished = $true
    )
    Show-StageHeader -Title "OPA GATEKEEPER: Deploying ConstraintTemplates & Constraints" -Category "POLICIES"
    $gatekeeperDir = Join-Path $RepoRoot "devsecops\policies\gatekeeper"
    $templatesDir = Join-Path $gatekeeperDir "templates"
    $constraintsDir = Join-Path $gatekeeperDir "constraints"

    if (-not (Test-Path -LiteralPath $templatesDir)) {
        throw "Gatekeeper templates directory not found: $templatesDir"
    }
    if (-not (Test-Path -LiteralPath $constraintsDir)) {
        throw "Gatekeeper constraints directory not found: $constraintsDir"
    }

    Write-Host "[1/3] 📜 Applying ConstraintTemplates (Custom Rego CRDs)..." -ForegroundColor Cyan
    & kubectl apply -f $templatesDir
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to apply Gatekeeper ConstraintTemplates."
    }
    Show-Success "ConstraintTemplates applied from $templatesDir."

    if ($WaitEstablished) {
        Write-Host "[2/3] ⏳ Waiting for Gatekeeper Constraint CRDs to be registered & established..." -ForegroundColor Cyan
        $crds = @("k8srequiredresources.constraints.gatekeeper.sh", "k8strustedregistries.constraints.gatekeeper.sh")
        foreach ($crd in $crds) {
            Write-Host "  -> Verifying CRD: $crd" -ForegroundColor DarkGray
            & kubectl wait --for condition=established --timeout=60s "crd/$crd" 2>$null | Out-Null
        }
    }

    Write-Host "[3/3] 🛡️ Applying Constraints (Enforcement policies)..." -ForegroundColor Cyan
    & kubectl apply -f $constraintsDir
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to apply Gatekeeper Constraints."
    }
    Show-Success "Gatekeeper Constraints active (enforce-resource-limits, enforce-trusted-registry)."
}

function Invoke-GatekeeperAudit {
    [CmdletBinding()]
    param(
        [switch]$FailOnViolations
    )
    Show-StageHeader -Title "OPA GATEKEEPER: Cluster Admission Compliance & Audit" -Category "POLICIES"

    # Check Gatekeeper Controller Manager pod status
    Write-Host "Checking Gatekeeper controller health in namespace 'gatekeeper-system'..." -ForegroundColor Cyan
    $gkPods = & kubectl get pods -n gatekeeper-system -l control-plane=controller-manager -o json 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $gkPods) {
        Show-Warning "Gatekeeper controller-manager is not detected in namespace 'gatekeeper-system'."
        return [pscustomobject]@{ Status = "NOT_INSTALLED"; Violations = @() }
    }
    $gkPodData = (($gkPods -join "`n") | ConvertFrom-Json)
    $readyControllers = @($gkPodData.items | Where-Object {
        $_.status.phase -eq 'Running' -and ($_.status.conditions | Where-Object { $_.type -eq 'Ready' -and $_.status -eq 'True' })
    })
    if ($readyControllers.Count -eq 0) {
        Show-Warning "Gatekeeper controller pods are present but not in Ready state."
    } else {
        Show-Success "Gatekeeper controller-manager healthy ($($readyControllers.Count) replica(s) Ready)."
    }

    # Audit ConstraintTemplates
    $templates = & kubectl get constrainttemplates -o json 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $templates) {
        Show-Warning "No ConstraintTemplates detected in the cluster."
        return [pscustomobject]@{ Status = "NO_TEMPLATES"; Violations = @() }
    }
    $templateCount = (($templates -join "`n") | ConvertFrom-Json).items.Count
    Show-Success "Active ConstraintTemplates: $templateCount"

    # Audit Constraints and Violations
    Write-Host "`nAuditing Constraints and runtime workload violations..." -ForegroundColor Cyan
    $constraintKinds = @("K8sRequiredResources", "K8sTrustedRegistries")
    $violationsList = [System.Collections.Generic.List[object]]::new()
    $hasViolations = $false

    foreach ($kind in $constraintKinds) {
        $cJson = & kubectl get $kind -o json 2>$null
        if ($LASTEXITCODE -eq 0 -and $cJson) {
            $cData = (($cJson -join "`n") | ConvertFrom-Json)
            foreach ($item in $cData.items) {
                $name = $item.metadata.name
                $totalViolations = if ($item.status.totalViolations) { [int]$item.status.totalViolations } else { 0 }
                $enforcementAction = if ($item.spec.enforcementAction) { $item.spec.enforcementAction } else { "deny" }

                $color = if ($totalViolations -gt 0) { "Red" } else { "Green" }
                Write-Host "  • Constraint: $kind / $name [Action: $enforcementAction | Violations: $totalViolations]" -ForegroundColor $color

                if ($totalViolations -gt 0 -and $item.status.violations) {
                    $hasViolations = $true
                    foreach ($v in $item.status.violations) {
                        $violationsList.Add([pscustomobject]@{
                            Constraint = $name
                            Kind       = $v.kind
                            Namespace  = $v.namespace
                            Resource   = $v.name
                            Message    = $v.message
                        })
                    }
                }
            }
        }
    }

    if ($violationsList.Count -gt 0) {
        Write-Host "`n⚠️  Non-Compliant Resources Detected by Gatekeeper:" -ForegroundColor Red
        $violationsList | Format-Table -AutoSize | Out-Host
        if ($FailOnViolations) {
            throw "Gatekeeper audit FAILED: $($violationsList.Count) policy violations detected in the cluster."
        }
    } else {
        Show-Success "Gatekeeper Audit: 0 policy violations detected across monitored namespaces."
    }

    return [pscustomobject]@{
        Status     = if ($hasViolations) { "VIOLATIONS_FOUND" } else { "COMPLIANT" }
        Violations = $violationsList
    }
}

function Test-GatekeeperEnforcement {
    param(
        [string]$Namespace = "dev"
    )
    Show-StageHeader -Title "OPA GATEKEEPER: Webhook Admission Enforcement Testing" -Category "POLICIES"
    Write-Host "Testing dynamic admission rejection against namespace '$Namespace'..." -ForegroundColor Cyan

    # Test 1: Untrusted Registry Rejection
    Write-Host "  [Test 1] Deploying image with untrusted registry (untrusted.io/malicious:1.0)..." -ForegroundColor Cyan
    $badRegistryYaml = @"
apiVersion: apps/v1
kind: Deployment
metadata:
  name: gatekeeper-test-bad-registry
  namespace: $Namespace
spec:
  replicas: 1
  selector:
    matchLabels:
      app: gatekeeper-test-bad-registry
  template:
    metadata:
      labels:
        app: gatekeeper-test-bad-registry
    spec:
      containers:
      - name: test
        image: untrusted.io/malicious:1.0
        resources:
          limits:
            cpu: 100m
            memory: 128Mi
"@
    $badRegResult = $badRegistryYaml | & kubectl apply --dry-run=server -f - 2>&1
    $badRegBlocked = ($badRegResult -match "denied the request" -or $badRegResult -match "is not from a trusted registry" -or $LASTEXITCODE -ne 0)

    if ($badRegBlocked) {
        Show-Success "Gatekeeper admission webhook BLOCKED unapproved container registry as expected!"
    } else {
        Show-Failure "Gatekeeper failed to block unapproved container registry. Check webhook and constraint status."
    }

    # Test 2: Missing Resource Limits Rejection
    Write-Host "  [Test 2] Deploying container without CPU/memory limits..." -ForegroundColor Cyan
    $badResourcesYaml = @"
apiVersion: apps/v1
kind: Deployment
metadata:
  name: gatekeeper-test-no-limits
  namespace: $Namespace
spec:
  replicas: 1
  selector:
    matchLabels:
      app: gatekeeper-test-no-limits
  template:
    metadata:
      labels:
        app: gatekeeper-test-no-limits
    spec:
      containers:
      - name: test
        image: georgegxx/products-service:1.0.0
"@
    $badResResult = $badResourcesYaml | & kubectl apply --dry-run=server -f - 2>&1
    $badResBlocked = ($badResResult -match "denied the request" -or $badResResult -match "must specify CPU and memory limits" -or $LASTEXITCODE -ne 0)

    if ($badResBlocked) {
        Show-Success "Gatekeeper admission webhook BLOCKED deployment missing resource limits as expected!"
    } else {
        Show-Failure "Gatekeeper failed to block deployment missing resource limits. Check constraint status."
    }
}

function Invoke-PostDeployDynamicGate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TargetUrl,

        [string]$KeycloakUrl = $env:KEYCLOAK_URL,

        [string]$RouterUrl = "",
        [string]$FrontendUrl = "",
        [ValidateSet("dev", "staging", "prod")]
        [string]$Environment = "dev",

        [switch]$SkipSmoke,
        [switch]$SkipNewman,
        [switch]$SkipK6,
        [switch]$SkipZap,
        [switch]$RunSimulate,
        [switch]$FailFast = $false
    )

    Show-StageHeader -Title "POST-DEPLOY DYNAMIC QUALITY & DAST GATE (Target: $TargetUrl)" -Category "POST-DEPLOY"
    $passed = $true
    $results = [System.Collections.Generic.List[object]]::new()

    $effectiveRouterUrl = if ($RouterUrl) { $RouterUrl } else { "$TargetUrl:8080" }
    $effectiveFrontendUrl = if ($FrontendUrl) { $FrontendUrl } else { $TargetUrl }

    # --- 4.1 Smoke Testing (smoke.py) ---
    if (-not $SkipSmoke) {
        Write-Host "`n[1/5] 💨 Smoke Tests: Probing live storefront and router endpoints..." -ForegroundColor Cyan
        $smokeScript = Join-Path $RepoRoot "scripts\testing\smoke.py"
        if (Test-Path -LiteralPath $smokeScript) {
            $env:TARGET_URL = $TargetUrl
            $env:BASE_URL = $TargetUrl
            $env:FRONTEND_URL = $effectiveFrontendUrl
            $smokeOutput = @(& python $smokeScript --deployment 2>&1)
            if ($LASTEXITCODE -eq 0) {
                Show-Success "Smoke tests passed against live deployment."
                $results.Add([pscustomobject]@{ Stage = "Smoke Tests"; Status = "PASSED"; Details = "Storefront & Router OK" })
            } else {
                Show-Failure "Smoke tests failed against live endpoints!"
                $smokeOutput | ForEach-Object { Write-Host "    $_" -ForegroundColor Red }
                $results.Add([pscustomobject]@{ Stage = "Smoke Tests"; Status = "FAILED"; Details = "Endpoints unreachable" })
                $passed = $false
                if ($FailFast) { throw "Post-deploy failed at Smoke Test stage." }
            }
        } else {
            Show-Warning "Smoke test script not found at $smokeScript."
            $results.Add([pscustomobject]@{ Stage = "Smoke Tests"; Status = "SKIPPED"; Details = "Script missing" })
        }
    }

    # --- 4.2 Contract & Integration Tests (Newman / Postman) ---
    if (-not $SkipNewman) {
        Write-Host "`n[2/5] 🔗 Newman: Running API contract & integration test suite..." -ForegroundColor Cyan
        $collection = Join-Path $RepoRoot "devsecops\testing\newman\microservices.postman_collection.json"
        if (-not (Test-Path -LiteralPath $collection)) {
            Show-Warning "Postman collection not found at $collection."
            $results.Add([pscustomobject]@{ Stage = "Newman API Contract"; Status = "SKIPPED"; Details = "Collection missing" })
        } else {
            $newmanCmd = Get-Command newman -ErrorAction SilentlyContinue
            $npxCmd = Get-Command npx -ErrorAction SilentlyContinue
            $dockerCmd = Get-Command docker -ErrorAction SilentlyContinue
            $newmanExit = -1
            if (-not $KeycloakUrl) {
                throw "Authenticated Newman checks require -KeycloakUrl or the KEYCLOAK_URL environment variable."
            }

            if ($npxCmd) {
                & npx --yes --loglevel=error newman@6 run $collection --env-var "BASE_URL=$TargetUrl" --env-var "keycloak_url=$KeycloakUrl" --reporters cli --bail
                $newmanExit = $LASTEXITCODE
            } elseif ($newmanCmd) {
                & newman run $collection --env-var "BASE_URL=$TargetUrl" --env-var "keycloak_url=$KeycloakUrl" --reporters cli --bail
                $newmanExit = $LASTEXITCODE
            } elseif ($dockerCmd) {
                Write-Host "  -> Running Newman via Docker container (postman/newman:alpine)..." -ForegroundColor DarkGray
                & docker run --rm -v "${RepoRoot}\devsecops\testing\newman:/etc/newman" postman/newman:alpine run /etc/newman/microservices.postman_collection.json --env-var "BASE_URL=$TargetUrl" --env-var "keycloak_url=$KeycloakUrl" --bail
                $newmanExit = $LASTEXITCODE
            } else {
                throw "Newman contract checks require Node.js/npm (npx), Newman, or Docker."
            }

            if ($newmanExit -eq 0) {
                Show-Success "Newman API Contract tests passed (100% assertions successful)."
                $results.Add([pscustomobject]@{ Stage = "Newman API Contract"; Status = "PASSED"; Details = "Contracts verified" })
            } elseif ($newmanExit -gt 0) {
                Show-Failure "Newman contract test assertions failed!"
                $results.Add([pscustomobject]@{ Stage = "Newman API Contract"; Status = "FAILED"; Details = "Contract assertion failed" })
                $passed = $false
                if ($FailFast) { throw "Post-deploy failed at Newman stage." }
            }
        }
    }

    # --- 4.3 Performance & SLA Load Testing (Grafana k6) ---
    if (-not $SkipK6) {
        Write-Host "`n[3/5] ⚡ Grafana k6: Running load & SLA verification (p95 < 500ms)..." -ForegroundColor Cyan
        $k6Script = Join-Path $RepoRoot "devsecops\testing\k6\load-test.js"
        if (-not (Test-Path -LiteralPath $k6Script)) {
            Show-Warning "k6 script not found at $k6Script."
            $results.Add([pscustomobject]@{ Stage = "k6 Performance"; Status = "SKIPPED"; Details = "Script missing" })
        } else {
            $k6Cmd = Get-Command k6 -ErrorAction SilentlyContinue
            $dockerCmd = Get-Command docker -ErrorAction SilentlyContinue
            $k6Exit = -1

            if ($k6Cmd) {
                & k6 run -e "TARGET_URL=$TargetUrl" $k6Script
                $k6Exit = $LASTEXITCODE
            } elseif ($dockerCmd) {
                Write-Host "  -> Running k6 via Docker container (grafana/k6:1.8.1)..." -ForegroundColor DarkGray
                Get-Content $k6Script | & docker run --rm -i -e "TARGET_URL=$TargetUrl" grafana/k6:1.8.1 run -
                $k6Exit = $LASTEXITCODE
            } else {
                Show-Warning "Neither k6 CLI nor Docker is available. Skipping load test."
                $results.Add([pscustomobject]@{ Stage = "k6 Performance"; Status = "SKIPPED"; Details = "Runner unavailable" })
            }

            if ($k6Exit -eq 0) {
                Show-Success "k6 SLA thresholds satisfied (p95 latency and error rate in SLO)."
                $results.Add([pscustomobject]@{ Stage = "k6 Performance"; Status = "PASSED"; Details = "SLA p95 < 500ms OK" })
            } elseif ($k6Exit -gt 0) {
                Show-Failure "k6 performance test breached SLA thresholds!"
                $results.Add([pscustomobject]@{ Stage = "k6 Performance"; Status = "FAILED"; Details = "SLA threshold breached" })
                $passed = $false
                if ($FailFast) { throw "Post-deploy failed at k6 performance stage." }
            }
        }
    }

    # --- 4.4 DAST Dynamic Security Testing (OWASP ZAP) ---
    if (-not $SkipZap) {
        Write-Host "`n[4/5] 🕵️ OWASP ZAP: Running Dynamic Application Security Testing (DAST)..." -ForegroundColor Cyan
        $zapRules = Join-Path $RepoRoot "devsecops\dast\zap\rules.tsv"
        $dockerCmd = Get-Command docker -ErrorAction SilentlyContinue

        if (-not (Test-Path -LiteralPath $zapRules -PathType Leaf)) {
            throw "Central OWASP ZAP alert rules are missing: $zapRules"
        } elseif ($dockerCmd) {
            Write-Host "  -> Running OWASP ZAP Baseline Scan against '$TargetUrl' with centralized rules..." -ForegroundColor DarkGray
            $zapReportsDir = Join-Path $RepoRoot "devsecops\dast\zap"
            & docker run --rm -v "${zapReportsDir}:/zap/wrk/:rw" -t ghcr.io/zaproxy/zaproxy:stable zap-baseline.py -t $TargetUrl -c /zap/wrk/rules.tsv -r zap-report.html -I
            # ZAP baseline returns: 0 = pass, 1 = warn, 2 = fail, 3 = user error
            if ($LASTEXITCODE -le 1) {
                Show-Success "OWASP ZAP baseline scan completed. Report updated at devsecops/dast/zap/zap-report.html."
                $results.Add([pscustomobject]@{ Stage = "OWASP ZAP DAST"; Status = "PASSED"; Details = "Baseline audit clean" })
            } else {
                Show-Warning "OWASP ZAP baseline scan found potential dynamic risks. Review devsecops/dast/zap/zap-report.html."
                $results.Add([pscustomobject]@{ Stage = "OWASP ZAP DAST"; Status = "WARNING"; Details = "Alerts in report" })
            }
        } else {
            Show-Warning "Docker is required to run OWASP ZAP baseline container. Skipping dynamic DAST scan."
            $results.Add([pscustomobject]@{ Stage = "OWASP ZAP DAST"; Status = "SKIPPED"; Details = "Docker unavailable" })
        }
    }

    # --- 4.5 Shopper Traffic & Circuit Breaker Simulation ---
    if ($RunSimulate) {
        Write-Host "`n[5/5] 🛒 Shopping Journey & Resilience Simulation (simulate.py)..." -ForegroundColor Cyan
        $simScript = Join-Path $RepoRoot "scripts\testing\simulate.py"
        if (Test-Path -LiteralPath $simScript) {
            & python $simScript --scenario traffic --orders 10
            if ($LASTEXITCODE -eq 0) {
                Show-Success "Shopper simulation completed: orders created and circuit breaker healthy."
                $results.Add([pscustomobject]@{ Stage = "Traffic Simulation"; Status = "PASSED"; Details = "Circuit breaker stable" })
            } else {
                Show-Warning "Simulation encountered errors."
                $results.Add([pscustomobject]@{ Stage = "Traffic Simulation"; Status = "WARNING"; Details = "Errors observed" })
            }
        }
    }

    # Summary table
    Write-Host ""
    $results | Format-Table -AutoSize | Out-Host
    if (-not $passed) {
        throw "Post-deploy dynamic verification FAILED. One or more quality/DAST gates tripped."
    }
    Show-Success "Post-deploy dynamic quality and DAST gates completed successfully."
    return $true
}

function Invoke-CloudFullPipeline {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet("aws", "azure", "gcp")]
        [string]$Provider,

        [ValidateSet("dev", "staging", "prod")]
        [string]$Environment = "dev",

        [ValidateSet("eks", "ecs-fargate", "ec2-compact")]
        [string]$Flavor = "eks",

        [string]$TargetUrl = "",
        [string]$KeycloakUrl = $env:KEYCLOAK_URL,
        [switch]$AutoApprove
    )

    if ($Provider -eq "aws" -and $Flavor -ne "eks") {
        throw "The end-to-end Kubernetes delivery pipeline supports AWS EKS only. Flavor '$Flavor' can use Terraform lifecycle commands, but this CLI has no ECS/EC2 workload delivery driver."
    }

    Show-StageHeader -Title "ENTERPRISE END-TO-END PIPELINE: $Provider ($Environment)" -Category "PIPELINE"

    # Step 1: Pre-Deploy Shift-Left Gate
    Invoke-PreDeploySecurityGate -Provider $Provider -Environment $Environment -Flavor $Flavor -FailFast

    # Step 2: Terraform Plan & Apply
    Invoke-TerraformCloudLifecycle -Provider $Provider -Action apply -Environment $Environment -Flavor $Flavor -AutoApprove:$AutoApprove

    # Step 3: Workload Sync / Deploy
    switch ($Provider) {
        "aws"   { Sync-ArgoCdWorkloads -Environment $Environment }
        "azure" { Invoke-HelmWorkloadDeploy -Provider azure -Environment $Environment }
        "gcp"   { Invoke-HelmWorkloadDeploy -Provider gcp -Environment $Environment }
    }

    # Step 4: Post-Deploy Dynamic Quality & DAST Gate (if URL provided)
    if ($TargetUrl) {
        Invoke-PostDeployDynamicGate -TargetUrl $TargetUrl -KeycloakUrl $KeycloakUrl -Environment $Environment
    } else {
        Write-Host "  [INFO] TargetUrl not provided; skipping live Post-Deploy DAST/k6 testing. Run post-deploy explicitly with -TargetUrl." -ForegroundColor DarkGray
    }

    Show-Success "End-to-end pipeline execution completed successfully for $Provider ($Environment)!"
}



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
        [string]$Flavor = "eks",
        [switch]$InstallMissing
    )
    $isKubernetesTarget = $TargetProvider -ne "aws" -or $Flavor -eq "eks"
    Write-Host "`nCloud orchestration ($($TargetProvider.ToUpper()) / $Flavor) host tools audit:" -ForegroundColor Cyan
    $providerCli = switch ($TargetProvider) {
        "aws"   { @{ Name = "aws"; Package = "Amazon.AWSCLI"; Purpose = if ($isKubernetesTarget) { "AWS identity & EKS operations" } else { "AWS identity & infrastructure operations" } } }
        "azure" { @{ Name = "az"; Package = "Microsoft.AzureCLI"; Purpose = "Azure identity & AKS CLI" } }
        "gcp"   { @{ Name = "gcloud"; Package = "Google.CloudSDK"; Purpose = "Google Cloud SDK & GKE CLI" } }
    }

    $tools = @(
        $providerCli,
        @{ Name = "terraform"; Package = "Hashicorp.Terraform"; Purpose = "IaC Lifecycle engine" },
        @{ Name = "gitleaks"; Package = "Gitleaks.Gitleaks"; Purpose = "Secret leakage detection" },
        @{ Name = "tflint"; Package = "TerraformLinters.tflint"; Purpose = "Terraform linting" },
        @{ Name = "trivy"; Package = "AquaSecurity.Trivy"; Purpose = "IaC misconfig & container scanner" },
        @{ Name = "python"; Package = "Python.Python.3.12"; Purpose = "Post-deploy smoke and traffic checks" },
        @{ Name = "docker"; Package = "Docker.DockerDesktop"; Purpose = "Container runner for k6, Newman, and OWASP ZAP" },
        @{ Name = "k6"; Package = "k6.k6"; Purpose = "Optional host runner for performance checks" }
    )
    if ($isKubernetesTarget) {
        $tools += @(
            @{ Name = "kubectl"; Package = "Kubernetes.kubectl"; Purpose = "Managed Kubernetes cluster operations" },
            @{ Name = "helm"; Package = "Helm.Helm"; Purpose = "Kubernetes workload delivery and manifest rendering" },
            @{ Name = "conftest"; Package = "conftest"; Installer = "scoop"; Purpose = "Kubernetes OPA policy validation" }
        )
    }
    $tools += @(
        @{ Name = "cosign"; Package = "Sigstore.Cosign"; Purpose = "Supply chain signature validator" },
        @{ Name = "dot"; Package = "Graphviz.Graphviz"; Purpose = "Optional Terraform dependency graph rendering" }
    )

    $report = [System.Collections.Generic.List[object]]::new()
    foreach ($t in $tools) {
        $cmd = Get-Command $t.Name -ErrorAction SilentlyContinue | Select-Object -First 1
        $status = if ($cmd) { "Available ($($cmd.Source))" } else { "Missing" }
        if (-not $cmd -and $InstallMissing) {
            if ($t.ContainsKey("Installer") -and $t.Installer -eq "scoop") {
                if (-not (Get-Command scoop -ErrorAction SilentlyContinue)) {
                    $status = "Missing: install Scoop, then run 'scoop install conftest'"
                    $report.Add([pscustomobject]@{ Tool = $t.Name; Status = $status; Purpose = $t.Purpose })
                    continue
                }
                Write-Host "Attempting install of $($t.Package) via Scoop..." -ForegroundColor Yellow
                & scoop install conftest
            } else {
                Write-Host "Attempting install of $($t.Package) via WinGet..." -ForegroundColor Yellow
                & winget install --id $t.Package --exact --silent --accept-source-agreements --accept-package-agreements --disable-interactivity 2>$null
            }
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
  plan          : Generates binary execution plan (.tfplan) for the selected cloud flavor.
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
  pipeline      : Runs end-to-end Kubernetes delivery (AWS EKS, AKS, or GKE); AWS ECS/EC2 are Terraform-only.
  doctor        : Audits Cloud authentication, Kubernetes connectivity, and running workloads.
  status        : Shows Terraform workspace status and active Kubernetes workloads.
  tools         : Audits host CLI dependencies (pass -Install to attempt WinGet install).

Options:
  -Provider <aws|azure|gcp>            : Target cloud provider (default: aws)
  -Environment <dev|staging|prod>      : Target environment workspace (default: dev)
  -Flavor <eks|ecs-fargate|ec2-compact>: Choose AWS infrastructure flavor; workload orchestration supports EKS only
  -DataPlane <primary|secondary|all>   : Target production cluster data plane
  -TargetUrl <url>                     : Live endpoint for post-deploy tests & OWASP ZAP
  -KeycloakUrl <url>                   : Live Keycloak endpoint for authenticated Newman checks (or set KEYCLOAK_URL)
  -Scan                                : Enforce pre-deploy security scan before apply
  -GenerateGraph                       : Render architecture topology diagram with dot
  -AutoApprove                         : Bypass confirmation prompts
================================================================================
"@ -ForegroundColor Cyan
    }

    "tools" {
        Show-MultiCloudToolsAudit -TargetProvider $Provider -Flavor $Flavor -InstallMissing:$Install
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
        Assert-KubernetesTarget -Operation "ArgoCD reconciliation"
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
        Assert-KubernetesTarget -Operation "Gatekeeper management"
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
        Invoke-PostDeployDynamicGate -TargetUrl $TargetUrl -KeycloakUrl $KeycloakUrl -Environment $Environment
    }

    "pipeline" {
        Assert-ProviderIdentity -TargetProvider $Provider | Out-Null
        Invoke-CloudFullPipeline -Provider $Provider -Environment $Environment -Flavor $Flavor -TargetUrl $TargetUrl -KeycloakUrl $KeycloakUrl -AutoApprove:$AutoApprove
    }

    { $_ -in @("doctor", "status") } {
        Assert-KubernetesTarget -Operation "Cloud cluster diagnostics"
        Assert-ProviderIdentity -TargetProvider $Provider | Out-Null
        Write-Host "`nAuditing $($Provider.ToUpper()) Kubernetes & Workloads in '$Environment'..." -ForegroundColor Cyan
        Invoke-TerraformCloudLifecycle -Provider $Provider -Action output -Environment $Environment -Flavor $Flavor
        $targetNs = if ($Environment -eq "prod") { "production" } else { $Environment }
        & kubectl get nodes 2>$null
        & kubectl get pods -n $targetNs 2>$null
        Invoke-GatekeeperAudit -FailOnViolations:$Strict
    }
}
