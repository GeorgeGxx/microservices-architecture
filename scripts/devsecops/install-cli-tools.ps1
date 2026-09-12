# ==============================================================================
# Winget DevSecOps & Platform CLI Tool Auditor & Installer
# Project: microservices-architecture
#
# Audits required Windows CLI tools and optionally installs missing tools via Winget.
# Ignored per user requirements: OpenTofu, k9s, kubectx/kubens, argocd cli,
#                                 kustomize, eksctl, lazygit, jq, yq.
# ==============================================================================
[CmdletBinding()]
param(
    [switch]$Install = $false,
    [switch]$Force = $false
)

$ErrorActionPreference = "Continue"
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

$tools = @(
    # IaC, Linters & Graphviz
    @{ Id = "Hashicorp.Terraform";     Cmd = "terraform";   Category = "IaC";          Desc = "Multi-Cloud Infrastructure-as-Code Engine" },
    @{ Id = "TerraformLinters.tflint"; Cmd = "tflint";      Category = "IaC";          Desc = "Linter for Terraform modules and provider configurations" },
    @{ Id = "Infracost.Infracost";     Cmd = "infracost";   Category = "IaC";          Desc = "Cloud FinOps cost breakdown before applying IaC" },
    @{ Id = "Graphviz.Graphviz";       Cmd = "dot";         Category = "IaC";          Desc = "Visual dependency graph generator (terraform graph | dot)" },

    # DevSecOps & Cryptography
    @{ Id = "Gitleaks.Gitleaks";       Cmd = "gitleaks";    Category = "Security";     Desc = "Hardcoded secret and credential scanner for git repository" },
    @{ Id = "AquaSecurity.Trivy";      Cmd = "trivy";       Category = "Security";     Desc = "Vulnerability, SBOM, and misconfiguration container/Helm scanner" },
    @{ Id = "Sigstore.Cosign";         Cmd = "cosign";      Category = "Security";     Desc = "Cryptographic signing and verification for OCI container images" },
    @{ Id = "Hashicorp.Vault";         Cmd = "vault";       Category = "Security";     Desc = "Dynamic secrets engine, PKI intermediate CA & transit encryption" },

    # Kubernetes & Service Mesh
    @{ Id = "Kubernetes.minikube";     Cmd = "minikube";    Category = "Kubernetes";   Desc = "Local enterprise Kubernetes cluster runtime" },
    @{ Id = "Kubernetes.kubectl";      Cmd = "kubectl";     Category = "Kubernetes";   Desc = "Kubernetes cluster control CLI" },
    @{ Id = "Helm.Helm";               Cmd = "helm";        Category = "Kubernetes";   Desc = "Package manager for Kubernetes umbrella charts and dependencies" },
    @{ Id = "istioctl";                Cmd = "istioctl";    Category = "Kubernetes";   Desc = "Istio service mesh control plane management CLI" },

    # Runtimes & Cloud Tunnels
    @{ Id = "Docker.DockerDesktop";    Cmd = "docker";      Category = "Runtime";      Desc = "OCI container runtime and BuildKit engine" },
    @{ Id = "Apache.Maven";            Cmd = "mvn";         Category = "Runtime";      Desc = "Java 21 / Spring Boot build orchestrator" },
    @{ Id = "OpenJS.NodeJS.LTS";       Cmd = "node";        Category = "Runtime";      Desc = "Angular 21 storefront runtime environment" },
    @{ Id = "Git.Git";                 Cmd = "git";         Category = "Runtime";      Desc = "Distributed version control system" },
    @{ Id = "Cloudflare.cloudflared";  Cmd = "cloudflared"; Category = "Networking";   Desc = "Zero-trust application tunnel supervisor" }
)

Write-Host ""
Write-Host "==============================================================================" -ForegroundColor Cyan
Write-Host " [TOOLS] MICROSERVICES PLATFORM CLI TOOLS AUDIT & WINGET INSTALLER" -ForegroundColor Cyan
Write-Host "==============================================================================" -ForegroundColor Cyan

$results = @()

foreach ($t in $tools) {
    $existing = Get-Command $t.Cmd -ErrorAction SilentlyContinue
    $isInstalled = ($null -ne $existing)

    $versionStr = "Not Installed"
    if ($isInstalled) {
        $fileVer = $existing.FileVersionInfo.ProductVersion
        if ($fileVer) {
            $versionStr = $fileVer.Trim()
        } elseif ($existing.Version) {
            $versionStr = $existing.Version.ToString()
        } else {
            $versionStr = "Installed"
        }
        if ($versionStr.Length -gt 35) { $versionStr = $versionStr.Substring(0, 32) + "..." }
    }

    $results += [PSCustomObject]@{
        Category  = $t.Category
        Command   = $t.Cmd
        Status    = if ($isInstalled) { "INSTALLED" } else { "MISSING" }
        Version   = $versionStr
        PackageId = $t.Id
        Desc      = $t.Desc
        Installed = $isInstalled
    }
}

$results | Format-Table -Property Category, Command, Status, Version, PackageId -AutoSize

$missing = @($results | Where-Object { -not $_.Installed })

if ($missing.Count -eq 0) {
    Write-Host "`n[SUCCESS] All $($results.Count) audited platform CLI tools are installed and available in PATH!" -ForegroundColor Green
    return
}

Write-Host "`n[WARN] Found $($missing.Count) missing tool(s):" -ForegroundColor Yellow
foreach ($m in $missing) {
    Write-Host "  - $($m.Command) ($($m.PackageId)): $($m.Desc)" -ForegroundColor Gray
}

if (-not $Install) {
    Write-Host "`nTo automatically install missing tools using Winget, run with -Install:" -ForegroundColor Cyan
    Write-Host "  .\platform.ps1 tools -Install" -ForegroundColor Green
    Write-Host "Or execute directly:" -ForegroundColor Cyan
    Write-Host "  .\scripts\devsecops\install-cli-tools.ps1 -Install`n" -ForegroundColor Green
    return
}

Write-Host "`n[INFO] Starting automated installation of missing tools via Winget..." -ForegroundColor Cyan
foreach ($item in $missing) {
    Write-Host "  -> Installing $($item.PackageId) ($($item.Command))..." -ForegroundColor Yellow
    try {
        winget install --id $item.PackageId --exact --silent --accept-source-agreements --accept-package-agreements
        if ($LASTEXITCODE -eq 0) {
            Write-Host "    [OK] Successfully installed $($item.PackageId)" -ForegroundColor Green
        } else {
            Write-Host "    [WARN] Winget exited with code $LASTEXITCODE for $($item.PackageId)" -ForegroundColor Red
        }
    } catch {
        Write-Host "    [ERR] Error installing $($item.PackageId): $_" -ForegroundColor Red
    }
}

Write-Host "`n[DONE] Installation process completed. Please refresh your PATH or restart your terminal." -ForegroundColor Green
