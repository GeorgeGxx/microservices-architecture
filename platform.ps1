# ==============================================================================
# Enterprise Platform Master CLI Orchestrator
# Multi-Platform (Minikube, AWS, Azure, GCP) & Multi-Stage (dev, staging, prod)
# ==============================================================================
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet("up", "bootstrap", "down", "stop", "destroy", "build", "doctor", "doctor-minikube", "doctor-cloud", "verify", "status", "finops", "cost", "tunnels", "secrets", "smoke", "tools", "graph", "security-scan", "plan", "apply", "rollback", "urls", "diagrams", "sync-diagrams", "help")]
    [string]$Command = "help",

    [Parameter(Position = 1)]
    [ValidateSet("minikube", "aws", "azure", "gcp")]
    [string]$Platform = "minikube",

    [ValidateSet("dev", "minikube", "staging", "prod")]
    [string]$Environment = "dev",

    [switch]$Build = $false,
    [switch]$Install = $false,
    [switch]$WithIstio = $true,
    [switch]$WithoutIstio = $false,
    [switch]$DeployCanary = $false,
    [switch]$SkipScans = $false,
    [switch]$AutoApprove = $false,
    [string]$LockId = "",
    [int]$Cpus = 12,
    [int]$MemoryMb = 12288,
    [string]$DiskSize = "80g",
    [switch]$Destroy = $false
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# Auto-discover known binary locations on Windows (e.g. Graphviz dot.exe)
$knownBinPaths = @(
    "C:\Program Files\Graphviz\bin",
    "C:\Program Files (x86)\Graphviz\bin",
    "$env:LOCALAPPDATA\Programs\Graphviz\bin",
    "$env:LOCALAPPDATA\Microsoft\WinGet\Links"
)
foreach ($bp in $knownBinPaths) {
    if ((Test-Path $bp) -and ($env:PATH -notlike "*$bp*")) {
        $env:PATH = "$bp;$env:PATH"
    }
}

$root = $PSScriptRoot
$minikubeScript = Join-Path $root "platform-minikube.ps1"
$awsScript      = Join-Path $root "platform-aws.ps1"
$azureScript    = Join-Path $root "platform-azure.ps1"
$gcpScript      = Join-Path $root "platform-gcp.ps1"
$toolsScript    = Join-Path $root "scripts\devsecops\install-cli-tools.ps1"
$costScript     = Join-Path $root "scripts\cloud\terraform\local-cost-estimator.py"
$tunnelsScript  = Join-Path $root "scripts\devsecops\supervise-tunnels.py"
$secretsScript  = Join-Path $root "scripts\devsecops\generate-secure-secrets.py"
$smokeScript    = Join-Path $root "scripts\devsecops\endpoint-smoke-test.py"
$verifyScript   = Join-Path $root "scripts\devsecops\verify-platform.ps1"
$drawioScript   = Join-Path $root "scripts\build\generate_drawio.py"

function Invoke-TargetValidation {
    param(
        [ValidateSet("minikube", "aws", "azure", "gcp")]
        [string]$TargetPlatform,

        [ValidateSet("dev", "minikube", "staging", "prod")]
        [string]$TargetEnvironment
    )

    $normalizedEnv = if ($TargetEnvironment -in @("dev", "minikube")) { "dev" } else { $TargetEnvironment }

    Write-Host "`n[VALIDATION] Running mesh validation for platform '$TargetPlatform' and environment '$normalizedEnv'..." -ForegroundColor Cyan

    if ($TargetPlatform -eq "minikube") {
        & (Join-Path $root "scripts\devsecops\verify-platform.ps1") -Mode minikube -Environment $normalizedEnv
    } else {
        & (Join-Path $root "scripts\devsecops\verify-platform.ps1") -Mode $TargetPlatform -Environment $normalizedEnv
    }
}

function Show-Banner {
    param([string]$Subtitle = "Unified Platform Engineering CLI")
    Write-Host ""
    Write-Host "================================================================================" -ForegroundColor Cyan
    Write-Host " 🚀 ENTERPRISE DEVSECOPS & MULTI-CLOUD PLATFORM CLI" -ForegroundColor Cyan
    Write-Host " Architecture: 4 Target Versions (Minikube, AWS, Azure, GCP) | 3 Environments (dev, staging, prod)" -ForegroundColor Cyan
    Write-Host "================================================================================" -ForegroundColor Cyan
    Write-Host " ▶ Mode: $Subtitle | Platform: [$($Platform.ToUpper())] | Environment: [$($Environment.ToUpper())]" -ForegroundColor Yellow
    Write-Host "--------------------------------------------------------------------------------" -ForegroundColor DarkGray
}

switch ($Command) {
    # --------------------------------------------------------------------------
    # Platform Lifecycle Orchestration (Delegates to Target Platform Script)
    # --------------------------------------------------------------------------
    { $_ -in @("up", "bootstrap") } {
        Show-Banner "Platform Ecosystem Bootstrap"
        switch ($Platform) {
            "minikube" {
                # Minikube local validation is already executed inside platform-minikube.ps1 to avoid duplicate mesh checks
                # and to preserve the final local bootstrap summary output.
                & $minikubeScript -Command up -Build:$Build -WithIstio:$WithIstio -WithoutIstio:$WithoutIstio -DeployCanary:$DeployCanary -SkipScans:$SkipScans -Cpus $Cpus -MemoryMb $MemoryMb -DiskSize $DiskSize
            }
            "aws" {
                $targetEnv = if ($Environment -in @("dev", "minikube")) { "dev" } else { $Environment }
                & $awsScript -Action apply -Environment $targetEnv -AutoApprove:$AutoApprove
                Invoke-TargetValidation -TargetPlatform aws -TargetEnvironment $targetEnv
            }
            "azure" {
                $targetEnv = if ($Environment -in @("dev", "minikube")) { "dev" } else { $Environment }
                & $azureScript -Action apply -Environment $targetEnv -AutoApprove:$AutoApprove
                Invoke-TargetValidation -TargetPlatform azure -TargetEnvironment $targetEnv
            }
            "gcp" {
                $targetEnv = if ($Environment -in @("dev", "minikube")) { "dev" } else { $Environment }
                & $gcpScript -Action apply -Environment $targetEnv -AutoApprove:$AutoApprove
                Invoke-TargetValidation -TargetPlatform gcp -TargetEnvironment $targetEnv
            }
        }
    }

    { $_ -in @("down", "stop") } {
        Show-Banner "Platform Teardown / Resource Pause"
        switch ($Platform) {
            "minikube" {
                & $minikubeScript -Command down -Destroy:$Destroy
            }
            "aws" {
                $targetEnv = if ($Environment -in @("dev", "minikube")) { "dev" } else { $Environment }
                & $awsScript -Action destroy -Environment $targetEnv -AutoApprove:$AutoApprove
            }
            "azure" {
                $targetEnv = if ($Environment -in @("dev", "minikube")) { "dev" } else { $Environment }
                & $azureScript -Action destroy -Environment $targetEnv -AutoApprove:$AutoApprove
            }
            "gcp" {
                $targetEnv = if ($Environment -in @("dev", "minikube")) { "dev" } else { $Environment }
                & $gcpScript -Action destroy -Environment $targetEnv -AutoApprove:$AutoApprove
            }
        }
    }

    "destroy" {
        Show-Banner "Complete Platform Purge"
        switch ($Platform) {
            "minikube" { & $minikubeScript -Command destroy }
            "aws"      { & $awsScript -Action destroy -Environment $Environment -AutoApprove:$AutoApprove }
            "azure"    { & $azureScript -Action destroy -Environment $Environment -AutoApprove:$AutoApprove }
            "gcp"      { & $gcpScript -Action destroy -Environment $Environment -AutoApprove:$AutoApprove }
        }
    }

    "plan" {
        Show-Banner "Terraform Infrastructure Plan"
        switch ($Platform) {
            "minikube" { & $minikubeScript -Command graph }
            "aws"      { & $awsScript -Action plan -Environment $Environment }
            "azure"    { & $azureScript -Action plan -Environment $Environment }
            "gcp"      { & $gcpScript -Action plan -Environment $Environment }
        }
    }

    "apply" {
        Show-Banner "Terraform Infrastructure Apply"
        switch ($Platform) {
            "minikube" { & $minikubeScript -Command up }
            "aws"      { & $awsScript -Action apply -Environment $Environment -AutoApprove:$AutoApprove }
            "azure"    { & $azureScript -Action apply -Environment $Environment -AutoApprove:$AutoApprove }
            "gcp"      { & $gcpScript -Action apply -Environment $Environment -AutoApprove:$AutoApprove }
        }
    }

    "rollback" {
        Show-Banner "Automated Emergency Rollback"
        switch ($Platform) {
            "minikube" {
                Write-Host "Executing Minikube Helm rollback on namespace 'dev'..." -ForegroundColor Yellow
                helm rollback microservices --namespace dev --wait --timeout 5m 2>$null
            }
            "aws"   { & $awsScript -Action rollback -Environment $Environment -LockId $LockId }
            "azure" { & $azureScript -Action rollback -Environment $Environment -LockId $LockId }
            "gcp"   { & $gcpScript -Action rollback -Environment $Environment -LockId $LockId }
        }
    }

    # --------------------------------------------------------------------------
    # Utility Commands (FinOps, Health, Secrets, Tools, Tunnels, Smoke)
    # --------------------------------------------------------------------------
    { $_ -in @("doctor", "verify", "status") } {
        Show-Banner "Platform Health & Diagnostic Audit"
        if ($Platform -eq "minikube") {
            & $minikubeScript -Command doctor
        } else {
            switch ($Platform) {
                "aws"   { & $awsScript -Action status -Environment $Environment }
                "azure" { & $azureScript -Action status -Environment $Environment }
                "gcp"   { & $gcpScript -Action status -Environment $Environment }
            }
        }
    }

    "doctor-minikube" {
        Show-Banner "Minikube Istio Validation"
        & (Join-Path $root "scripts\devsecops\verify-platform.ps1") -Mode minikube -Namespace $Environment
    }

    "doctor-cloud" {
        Show-Banner "Multi-Cloud Istio Validation"
        if ($Platform -eq "minikube") {
            Write-Host "This check is for AWS / Azure / GCP. Use -Platform aws|azure|gcp with this command." -ForegroundColor Yellow
            return
        }
        & (Join-Path $root "scripts\devsecops\verify-platform.ps1") -Mode $Platform -Environment $Environment
    }

    { $_ -in @("finops", "cost") } {
        Show-Banner "Air-Gapped FinOps Cost Breakdown & Savings"
        $targetCostEnv = if ($Platform -eq "minikube" -or $Environment -eq "minikube") { "minikube" } else { $Environment }
        python $costScript --env $targetCostEnv
    }

    "tools" {
        Show-Banner "Platform CLI Tools Auditor & Winget Installer"
        & $toolsScript -Install:$Install
    }

    "smoke" {
        Show-Banner "Microservice API Integration Smoke Tests"
        python $smokeScript --base-url http://127.0.0.1:8080
    }

    "tunnels" {
        Show-Banner "Background Port-Forward Tunnel Supervisor"
        python $tunnelsScript
    }

    "secrets" {
        Show-Banner "Zero-Trust Cryptographic Secret Generator"
        $ns = if ($Environment -in @("dev", "minikube")) { "dev" } else { $Environment }
        python $secretsScript --namespace $ns
    }

    "security-scan" {
        Show-Banner "Security Scans (Gitleaks, TFLint, Trivy, Cosign)"
        & $minikubeScript -Command security-scan
    }

    "graph" {
        Show-Banner "Visual Dependency Graph (Graphviz)"
        & $minikubeScript -Command graph
    }

    "build" {
        Show-Banner "Build Microservice & Frontend Container Images From Source"
        & $minikubeScript -Command build
    }

    "urls" {
        Show-Banner "Active Platform Web Dashboards & Management Consoles"
        Write-Host "┌──────────────────────────────┬────────────────────────────────────────────┬────────────────┐" -ForegroundColor Cyan
        Write-Host "│ DASHBOARD / WEB CONSOLE      │ LOCAL URL                                  │ CREDENTIALS    │" -ForegroundColor Cyan
        Write-Host "├──────────────────────────────┼────────────────────────────────────────────┼────────────────┤" -ForegroundColor Cyan
        Write-Host "│ 🌐 Angular Storefront        │ http://localhost:4200                      │ Open           │" -ForegroundColor White
        Write-Host "│ 🔌 API Gateway (Swagger UI)  │ http://localhost:8080/swagger-ui.html      │ Open           │" -ForegroundColor White
        Write-Host "│ 🔑 Keycloak IAM Console      │ http://localhost:8181                      │ admin / admin  │" -ForegroundColor White
        Write-Host "│ 🔒 HashiCorp Vault UI        │ http://localhost:8200                      │ root           │" -ForegroundColor White
        Write-Host "│ 🧭 Kiali Mesh Console        │ http://localhost:20001/kiali/              │ Anonymous      │" -ForegroundColor White
        Write-Host "│ 🐙 ArgoCD GitOps Server      │ https://localhost:8088                     │ admin / admin  │" -ForegroundColor White
        Write-Host "│ 📊 Grafana Observability     │ http://localhost:3000                      │ admin / admin  │" -ForegroundColor White
        Write-Host "│ 📈 Prometheus Web Console    │ http://localhost:9090/targets              │ Public         │" -ForegroundColor White
        Write-Host "└──────────────────────────────┴────────────────────────────────────────────┴────────────────┘" -ForegroundColor Cyan
        Write-Host "  ℹ️ All 10 communication tunnels remain open in background (including Tempo 3200 & Loki 3100)." -ForegroundColor DarkGray
        Write-Host "  ℹ️ Query distributed traces & logs directly within Grafana Explore: http://localhost:3000/explore`n" -ForegroundColor DarkGray
    }

    { $_ -in @("diagrams", "sync-diagrams") } {
        Show-Banner "Synchronize Architecture Blueprint (docs/Diagrams.drawio)"
        Write-Host "Regenerating docs/Diagrams.drawio across all 12 architectural tabs..." -ForegroundColor White
        python $drawioScript
    }

    default {
        Show-Banner "Command Usage & Multi-Platform Architecture Reference"
        Write-Host "USAGE:" -ForegroundColor Yellow
        Write-Host "  .\platform.ps1 <command> [-Platform minikube|aws|azure|gcp] [-Environment dev|staging|prod] [options]`n" -ForegroundColor White
        Write-Host "DIAGNOSTIC COMMANDS:" -ForegroundColor Yellow
        Write-Host "  doctor-minikube   Validate local Minikube + Istio installation and mesh readiness" -ForegroundColor White
        Write-Host "  doctor-cloud      Validate cloud provider + Istio gateway and ingress policy" -ForegroundColor White
        Write-Host "PLATFORMS:" -ForegroundColor Yellow
        Write-Host "  minikube    Local enterprise DevSecOps platform ('dev' namespace, 'develop' branch)" -ForegroundColor White
        Write-Host "  aws         Amazon Web Services (12 native modules, EKS, GitHub Actions CI, ArgoCD CD)" -ForegroundColor White
        Write-Host "  azure       Microsoft Azure Cloud (12 native modules, AKS, Azure DevOps unified CICD)" -ForegroundColor White
        Write-Host "  gcp         Google Cloud Platform (12 native modules, GKE, Bitbucket Pipelines CICD)" -ForegroundColor White
        Write-Host "`nCOMMANDS:" -ForegroundColor Yellow
        Write-Host "  up | bootstrap      Bootstrap target platform ecosystem (use -Build to compile from Dockerfiles)" -ForegroundColor White
        Write-Host "  build               Compile Java Maven & Angular Dockerfiles from source & load into Minikube" -ForegroundColor White
        Write-Host "  down | stop         Gracefully stop target platform or pause Minikube (preserves state)" -ForegroundColor White
        Write-Host "  destroy             Completely purge resources and state (-Destroy / destroy)" -ForegroundColor White
        Write-Host "  plan | apply        Run Terraform plan or apply on target platform modules" -ForegroundColor White
        Write-Host "  rollback            Execute emergency automated rollback & state unlock" -ForegroundColor White
        Write-Host "  doctor | verify     Deep health diagnostics on pods, NodePorts, and policies" -ForegroundColor White
        Write-Host "  finops | cost       Air-gapped FinOps cost breakdown and savings calculator" -ForegroundColor White
        Write-Host "  tools [-Install]    Audit and install CLI tools via Winget (excluding 9 ignored tools)" -ForegroundColor White
        Write-Host "  smoke               Run automated HTTP smoke tests against microservices" -ForegroundColor White
        Write-Host "  tunnels             Launch background resilient port-forwarding daemon" -ForegroundColor White
        Write-Host "  graph               Generate visual PNG dependency graph with Graphviz" -ForegroundColor White
        Write-Host "  diagrams            Synchronize and regenerate docs/Diagrams.drawio (12 pages)" -ForegroundColor White
        Write-Host "  urls                Display table of active service endpoints and credentials" -ForegroundColor White
        Write-Host "`nEXAMPLES:" -ForegroundColor Yellow
        Write-Host "  .\platform.ps1 up" -ForegroundColor Green
        Write-Host "  .\platform.ps1 up -Build" -ForegroundColor Green
        Write-Host "  .\platform.ps1 build" -ForegroundColor Green
        Write-Host "  .\platform.ps1 up -Platform minikube -WithIstio" -ForegroundColor Green
        Write-Host "  .\platform.ps1 plan -Platform aws -Environment staging" -ForegroundColor Green
        Write-Host "  .\platform.ps1 plan -Platform azure -Environment prod" -ForegroundColor Green
        Write-Host "  .\platform.ps1 plan -Platform gcp -Environment staging" -ForegroundColor Green
        Write-Host "  .\platform.ps1 diagrams" -ForegroundColor Green
        Write-Host "  .\platform.ps1 tools -Install" -ForegroundColor Green
        Write-Host "  .\platform.ps1 doctor" -ForegroundColor Green
        Write-Host "  .\platform.ps1 urls" -ForegroundColor Green
        Write-Host "================================================================================" -ForegroundColor Cyan
    }
}
