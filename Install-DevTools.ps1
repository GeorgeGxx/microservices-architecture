#Requires -Version 5.1
<#
.SYNOPSIS
    Audits or installs only the documented microservices-architecture CLI tools.
.DESCRIPTION
    Audit is the default and has no installation or machine-configuration side effects.
    Pass -Install to install missing tools through WinGet. Cloud CLIs and the
    kubectl-cost OpenCost plugin are opt-in because local Minikube/Compose use
    does not require cloud credentials or live cluster cost access.
.EXAMPLE
    .\Install-DevTools.ps1
.EXAMPLE
    .\Install-DevTools.ps1 -Install
.EXAMPLE
    .\Install-DevTools.ps1 -Install -IncludeCloudCli -InstallOpenCostPlugin
#>
[CmdletBinding()]
param(
    [switch] $Install,
    [switch] $IncludeCloudCli,
    [switch] $InstallOpenCostPlugin
)

$ErrorActionPreference = 'Stop'

# Inventory aligned with docs/LOCAL_DEPLOYMENT.md and Invoke-CliToolsAudit.
$tools = @(
    [pscustomobject]@{ Id = 'Hashicorp.Terraform';      Command = 'terraform';   Purpose = 'Terraform IaC' },
    [pscustomobject]@{ Id = 'TerraformLinters.tflint'; Command = 'tflint';      Purpose = 'Terraform linting' },
    [pscustomobject]@{ Id = 'Graphviz.Graphviz';        Command = 'dot';         Purpose = 'Terraform graph rendering' },
    [pscustomobject]@{ Id = 'Gitleaks.Gitleaks';       Command = 'gitleaks';    Purpose = 'Secret scanning' },
    [pscustomobject]@{ Id = 'AquaSecurity.Trivy';      Command = 'trivy';       Purpose = 'Image and IaC scanning' },
    [pscustomobject]@{ Id = 'Sigstore.Cosign';         Command = 'cosign';      Purpose = 'Image signature verification' },
    [pscustomobject]@{ Id = 'Hashicorp.Vault';         Command = 'vault';       Purpose = 'Vault CLI workflows' },
    [pscustomobject]@{ Id = 'Kubernetes.minikube';     Command = 'minikube';    Purpose = 'Local Kubernetes cluster' },
    [pscustomobject]@{ Id = 'Kubernetes.kubectl';      Command = 'kubectl';     Purpose = 'Kubernetes administration' },
    [pscustomobject]@{ Id = 'Helm.Helm';               Command = 'helm';        Purpose = 'Helm deployments' },
    [pscustomobject]@{ Id = 'Istio.Istio';             Command = 'istioctl';    Purpose = 'Istio mesh operations' },
    [pscustomobject]@{ Id = 'Docker.DockerDesktop';    Command = 'docker';      Purpose = 'Compose and image builds' },
    [pscustomobject]@{ Id = 'Apache.Maven';            Command = 'mvn';         Purpose = 'Spring Boot builds' },
    [pscustomobject]@{ Id = 'BellSoft.LibericaJDK.21'; Command = 'java';        Purpose = 'Java 21 runtime' },
    [pscustomobject]@{ Id = 'OpenJS.NodeJS.LTS';       Command = 'node';        Purpose = 'React/Vite build runtime' },
    [pscustomobject]@{ Id = 'Python.Python.3.12';      Command = 'python';      Purpose = 'Project automation scripts' },
    [pscustomobject]@{ Id = 'Git.Git';                 Command = 'git';         Purpose = 'Version control' },
    [pscustomobject]@{ Id = 'Cloudflare.cloudflared';  Command = 'cloudflared'; Purpose = 'Documented tunnel workflows' }
)

if ($IncludeCloudCli) {
    $tools += @(
        [pscustomobject]@{ Id = 'Amazon.AWSCLI';     Command = 'aws';    Purpose = 'AWS credentials and operations' },
        [pscustomobject]@{ Id = 'Microsoft.AzureCLI'; Command = 'az';     Purpose = 'Azure credentials and operations' },
        [pscustomobject]@{ Id = 'Google.CloudSDK';   Command = 'gcloud'; Purpose = 'GCP credentials and operations' }
    )
}

$logDirectory = Join-Path $env:TEMP 'microservices-architecture-devtools'
New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null
$logFile = Join-Path $logDirectory ("install-audit-{0}.log" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
$results = [System.Collections.Generic.List[object]]::new()

function Write-Status {
    param([string] $Message, [string] $Color = 'Gray')
    Write-Host $Message -ForegroundColor $Color
    Add-Content -LiteralPath $logFile -Value $Message
}

if ($Install -and -not (Get-Command winget -ErrorAction SilentlyContinue)) {
    throw "WinGet is required for installation. Install Microsoft's App Installer, then rerun this script."
}

$mode = if ($Install) { 'install missing' } else { 'audit only' }
Write-Status 'Microservices Architecture documented CLI audit' 'Cyan'
Write-Status ("Mode: {0}; cloud CLIs: {1}; OpenCost plugin: {2}" -f $mode, $IncludeCloudCli.IsPresent, $InstallOpenCostPlugin.IsPresent)

foreach ($tool in $tools) {
    $command = Get-Command $tool.Command -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $command -and $Install) {
        Write-Status ("Installing {0} ({1}) - {2}" -f $tool.Id, $tool.Command, $tool.Purpose) 'Yellow'
        & winget install --id $tool.Id --exact --silent --accept-source-agreements --accept-package-agreements --disable-interactivity 2>&1 | Tee-Object -FilePath $logFile -Append | Out-Host
        if ($LASTEXITCODE -ne 0) {
            $results.Add([pscustomobject]@{ Tool = $tool.Command; Package = $tool.Id; Status = "FAILED ($LASTEXITCODE)" })
            continue
        }
        $command = Get-Command $tool.Command -ErrorAction SilentlyContinue | Select-Object -First 1
    }

    $status = if ($command) { 'Available' } elseif ($Install) { 'Installed; reopen terminal to refresh PATH' } else { 'Missing' }
    $results.Add([pscustomobject]@{ Tool = $tool.Command; Package = $tool.Id; Status = $status })
}

if ($InstallOpenCostPlugin) {
    if (-not (Get-Command kubectl -ErrorAction SilentlyContinue)) {
        $results.Add([pscustomobject]@{ Tool = 'kubectl cost'; Package = 'Krew cost plugin'; Status = 'Missing: kubectl is required' })
    } elseif (-not (kubectl krew version 2>$null)) {
        if ($Install) {
            Write-Status 'Installing opt-in Krew package (Kubernetes.krew)...' 'Yellow'
            & winget install --id Kubernetes.krew --exact --silent --accept-source-agreements --accept-package-agreements --disable-interactivity 2>&1 | Tee-Object -FilePath $logFile -Append | Out-Host
            $env:PATH = "$env:PATH;$env:USERPROFILE\.krew\bin"
        }
        if (kubectl krew version 2>$null) {
            $installedPlugins = kubectl krew list 2>$null
        } else {
            $results.Add([pscustomobject]@{ Tool = 'kubectl cost'; Package = 'Krew cost plugin'; Status = 'Missing: Krew unavailable; install Kubernetes.krew or reopen terminal' })
            $installedPlugins = $null
        }
    } else {
        $installedPlugins = kubectl krew list 2>$null
    }
    if ($installedPlugins -and $installedPlugins -match '(?m)^cost\s*$') {
        $results.Add([pscustomobject]@{ Tool = 'kubectl cost'; Package = 'Krew cost plugin'; Status = 'Available' })
    } elseif ($installedPlugins -and $Install) {
        kubectl krew install cost 2>&1 | Tee-Object -FilePath $logFile -Append | Out-Host
        $pluginStatus = if ($LASTEXITCODE -eq 0) { 'Installed' } else { "FAILED ($LASTEXITCODE)" }
        $results.Add([pscustomobject]@{ Tool = 'kubectl cost'; Package = 'Krew cost plugin'; Status = $pluginStatus })
    } elseif ($installedPlugins) {
        $results.Add([pscustomobject]@{ Tool = 'kubectl cost'; Package = 'Krew cost plugin'; Status = 'Missing: rerun with -InstallOpenCostPlugin -Install' })
    }
}

$results | Format-Table -AutoSize
$results | Format-Table -AutoSize | Out-String | Add-Content -LiteralPath $logFile
$missing = @($results | Where-Object { $_.Status -eq 'Missing' -or $_.Status -like 'FAILED*' })
Write-Status ("Audit complete. Log: {0}" -f $logFile) 'Cyan'
if ($missing.Count -gt 0) {
    Write-Status ("{0} required/selected tool(s) are missing or failed. Rerun with -Install after reviewing the list." -f $missing.Count) 'Yellow'
    exit 1
}
