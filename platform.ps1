# ==============================================================================
# Enterprise Platform Unified CLI (DevSecOps Orchestrator)
# Single Entrypoint for Multi-Stage Infrastructure, Security, FinOps & Observability
# ==============================================================================
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet("bootstrap", "up", "verify", "doctor", "status", "finops", "cost", "tunnels", "secrets", "smoke", "teardown", "down", "urls", "help")]
    [string]$Command = "help",

    [Parameter(Position = 1)]
    [ValidateSet("dev", "minikube", "staging", "prod")]
    [string]$Environment = "dev",

    [switch]$WithAwsBackend = $false,
    [switch]$DeployCanary = $false,
    [int]$Cpus = 12,
    [int]$MemoryMb = 12288,
    [switch]$DeleteCluster = $false,
    [switch]$CleanTerraformState = $false
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

function Show-Banner {
    param([string]$Subtitle = "Unified Platform Engineering CLI")
    Write-Host ""
    Write-Host "╔══════════════════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║              🚀 GEORGEGXX ENTERPRISE DEVSECOPS PLATFORM CLI                   ║" -ForegroundColor Cyan
    Write-Host "║              Architecture: Multi-Stage (Minikube Dev / AWS Cloud)            ║" -ForegroundColor Cyan
    Write-Host "╚══════════════════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host "  ▶ Mode: $Subtitle | Target: [$($Environment.ToUpper())]" -ForegroundColor Yellow
    Write-Host "────────────────────────────────────────────────────────────────────────────────" -ForegroundColor DarkGray
}

$devsecopsDir = Join-Path $PSScriptRoot "scripts\devsecops"
$cloudDir = Join-Path $PSScriptRoot "scripts\cloud\terraform"

switch ($Command) {
    { $_ -in @("bootstrap", "up") } {
        Show-Banner "Platform Ecosystem Bootstrap"
        $script = Join-Path $devsecopsDir "bootstrap-multistage-devsecops.ps1"
        $params = @{
            Environment = if ($Environment -eq "minikube") { "dev" } else { $Environment }
            Cpus = $Cpus
            MemoryMb = $MemoryMb
            DeployCanary = $DeployCanary
            WithAwsBackend = $WithAwsBackend
        }
        & $script @params
    }

    { $_ -in @("verify", "doctor", "status") } {
        Show-Banner "Platform Health & Diagnostic Audit"
        $script = Join-Path $devsecopsDir "verify-platform.ps1"
        & $script
    }

    { $_ -in @("finops", "cost") } {
        Show-Banner "FinOps Cloud Cost Estimation (Air-Gapped)"
        $script = Join-Path $cloudDir "local-cost-estimator.py"
        $targetEnv = if ($Environment -eq "dev") { "minikube" } else { $Environment }
        python $script --env $targetEnv
    }

    "tunnels" {
        Show-Banner "Background Port-Forward Tunnel Supervisor"
        $script = Join-Path $devsecopsDir "supervise-tunnels.py"
        python $script
    }

    "secrets" {
        Show-Banner "Zero-Trust Cryptographic Secret Generator"
        $script = Join-Path $devsecopsDir "generate-secure-secrets.py"
        $ns = if ($Environment -eq "minikube") { "dev" } else { $Environment }
        python $script --namespace $ns
    }

    "smoke" {
        Show-Banner "End-to-End Microservice API Smoke Test"
        $script = Join-Path $devsecopsDir "endpoint-smoke-test.py"
        python $script
    }

    { $_ -in @("teardown", "down") } {
        Show-Banner "Platform Teardown & Resource Release"
        $script = Join-Path $devsecopsDir "teardown-local-devsecops.ps1"
        $params = @{
            DeleteCluster = $DeleteCluster
            CleanTerraformState = $CleanTerraformState
        }
        & $script @params
    }

    "urls" {
        Show-Banner "Active Platform Endpoints & Credentials"
        Write-Host "┌──────────────────────────────┬────────────────────────────────────────────┬────────────────┐" -ForegroundColor Cyan
        Write-Host "│ SERVICE NAME                 │ LOCAL URL                                  │ CREDENTIALS    │" -ForegroundColor Cyan
        Write-Host "├──────────────────────────────┼────────────────────────────────────────────┼────────────────┤" -ForegroundColor Cyan
        Write-Host "│ 🌐 Angular Frontend          │ http://localhost:4200                      │ Open           │" -ForegroundColor White
        Write-Host "│ 🔌 API Gateway (Swagger UI)  │ http://localhost:8080/swagger-ui.html      │ Open           │" -ForegroundColor White
        Write-Host "│ 🔑 Keycloak IAM Console      │ http://localhost:8181                      │ admin / admin  │" -ForegroundColor White
        Write-Host "│ 🔒 HashiCorp Vault UI        │ http://localhost:8200                      │ root           │" -ForegroundColor White
        Write-Host "│ 🧭 Kiali Service Mesh Graph  │ http://localhost:20001/kiali/              │ Anonymous      │" -ForegroundColor White
        Write-Host "│ 🐙 ArgoCD GitOps Server      │ https://localhost:8088                     │ admin / admin  │" -ForegroundColor White
        Write-Host "│ 📊 Grafana Observability     │ http://localhost:3000                      │ admin / admin  │" -ForegroundColor White
        Write-Host "│ 📈 Prometheus Targets        │ http://localhost:9090/targets              │ Public         │" -ForegroundColor White
        Write-Host "└──────────────────────────────┴────────────────────────────────────────────┴────────────────┘" -ForegroundColor Cyan
    }

    default {
        Show-Banner "Command Usage & Architecture Help"
        Write-Host "USAGE:" -ForegroundColor Yellow
        Write-Host "  .\platform.ps1 <command> [-Environment dev|staging|prod] [options]`n" -ForegroundColor White
        Write-Host "COMMANDS:" -ForegroundColor Yellow
        Write-Host "  bootstrap | up      Bootstrap full ecosystem (Minikube, Terraform, Istio, Apps, Tunnels)" -ForegroundColor White
        Write-Host "  verify | doctor     Deep diagnostic health check of all pods, NodePorts & OPA policies" -ForegroundColor White
        Write-Host "  finops | cost       Air-gapped FinOps cost breakdown (Minikube savings / Staging / Prod)" -ForegroundColor White
        Write-Host "  urls                Display table of all live endpoints and credentials" -ForegroundColor White
        Write-Host "  smoke               Run end-to-end HTTP smoke test across all business microservices" -ForegroundColor White
        Write-Host "  tunnels             Launch resilient background port-forward tunnels daemon" -ForegroundColor White
        Write-Host "  secrets             Generate zero-trust cryptographic secrets bundle" -ForegroundColor White
        Write-Host "  teardown | down     Pause Minikube or purge cluster (-DeleteCluster)" -ForegroundColor White
        Write-Host "`nOPTIONS:" -ForegroundColor Yellow
        Write-Host "  -Environment <env>  Target environment: 'dev' (default/Minikube), 'staging', 'prod'" -ForegroundColor White
        Write-Host "  -WithAwsBackend     Conditionally bootstrap AWS S3 backend & DynamoDB locking" -ForegroundColor White
        Write-Host "  -DeployCanary       Deploy canary version v2 alongside v1" -ForegroundColor White
        Write-Host "  -DeleteCluster      In teardown: completely delete Minikube and reclaim 80 GB disk" -ForegroundColor White
        Write-Host "`nEXAMPLES:" -ForegroundColor Yellow
        Write-Host "  .\platform.ps1 up" -ForegroundColor Green
        Write-Host "  .\platform.ps1 doctor" -ForegroundColor Green
        Write-Host "  .\platform.ps1 cost -Environment minikube" -ForegroundColor Green
        Write-Host "  .\platform.ps1 cost -Environment staging" -ForegroundColor Green
        Write-Host "  .\platform.ps1 urls" -ForegroundColor Green
        Write-Host "────────────────────────────────────────────────────────────────────────────────" -ForegroundColor DarkGray
    }
}
