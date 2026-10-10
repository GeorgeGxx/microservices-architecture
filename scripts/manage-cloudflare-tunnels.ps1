<#
.SYNOPSIS
    Manages Cloudflare Quick Tunnels for local DevSecOps post-deployment verification.
.DESCRIPTION
    Exposes local services (Frontend 5173, Cosmo Router 8080, Keycloak 8181) through
    ephemeral Cloudflare Quick Tunnels (*.trycloudflare.com), validates public edge
    reachability, and synchronizes the URLs with GitHub Actions repository variables.
.EXAMPLE
    .\scripts\manage-cloudflare-tunnels.ps1 -Action Start
.EXAMPLE
    .\scripts\manage-cloudflare-tunnels.ps1 -Action Status
.EXAMPLE
    .\scripts\manage-cloudflare-tunnels.ps1 -Action Stop
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet("Start", "Stop", "Status", "Restart")]
    [string]$Action = "Start",

    [switch]$UpdateGitHub = $true,
    [string]$Repo = "GeorgeGxx/microservices-architecture"
)

$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$rootDir = Split-Path -Parent $scriptDir
$stateFile = Join-Path $scriptDir ".cloudflare-tunnels.json"
$logDir = Join-Path $scriptDir ".tunnel-logs"

if (-not (Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}

function Show-Header {
    param([string]$Title)
    Write-Host "`n================================================================================" -ForegroundColor Cyan
    Write-Host " 🚇 $Title" -ForegroundColor Yellow
    Write-Host "================================================================================" -ForegroundColor Cyan
}

function Stop-AllTunnels {
    param([bool]$DisableInGitHub = $false)
    Show-Header "Stopping Active Cloudflare Tunnels"

    if (Test-Path $stateFile) {
        try {
            $state = Get-Content $stateFile -Raw | ConvertFrom-Json
            if ($state.processes) {
                foreach ($proc in $state.processes) {
                    if ($proc.pid) {
                        try {
                            $p = Get-Process -Id $proc.pid -ErrorAction SilentlyContinue
                            if ($p) {
                                Write-Host "  ▶ Stopping tunnel for $($proc.name) (PID $($proc.pid))..." -ForegroundColor White
                                Stop-Process -Id $proc.pid -Force -ErrorAction SilentlyContinue
                            }
                        } catch {}
                    }
                }
            }
        } catch {
            Write-Host "  [!] Warning reading state file: $_" -ForegroundColor Yellow
        }
        Remove-Item $stateFile -Force -ErrorAction SilentlyContinue
    }

    # Also kill any orphan cloudflared processes
    $orphans = Get-Process -Name "cloudflared" -ErrorAction SilentlyContinue
    if ($orphans) {
        Write-Host "  ▶ Cleaning up $($orphans.Count) cloudflared process(es)..." -ForegroundColor DarkGray
        $orphans | Stop-Process -Force -ErrorAction SilentlyContinue
    }

    Write-Host "  [OK] All Cloudflare tunnels stopped." -ForegroundColor Green

    if ($DisableInGitHub) {
        Write-Host "  ▶ Updating GitHub variable DEVSECOPS_POST_DEPLOY_ENABLED=false..." -ForegroundColor White
        try {
            & gh variable set DEVSECOPS_POST_DEPLOY_ENABLED --body "false" -R $Repo 2>$null
            Write-Host "  [OK] GitHub Actions post-deployment validation safely disabled." -ForegroundColor Green
        } catch {
            Write-Host "  [!] Could not update GitHub variable: $_" -ForegroundColor Yellow
        }
    }
}

function Get-TunnelStatus {
    Show-Header "Cloudflare Tunnels Health & Status"
    if (-not (Test-Path $stateFile)) {
        Write-Host "  No active Cloudflare tunnels recorded in $stateFile." -ForegroundColor Yellow
        return
    }

    $state = Get-Content $stateFile -Raw | ConvertFrom-Json
    Write-Host "Started at: $($state.startedAt)" -ForegroundColor DarkGray

    $table = @()
    foreach ($item in $state.processes) {
        $p = Get-Process -Id $item.pid -ErrorAction SilentlyContinue
        $isRunning = ($null -ne $p)
        $httpStatus = "N/A"
        if ($isRunning -and $item.url) {
            try {
                if ($item.name -eq "router") {
                    $res = Invoke-RestMethod -Uri "$($item.url)/graphql" -Method Post -Body '{"query":"{ __typename }"}' -ContentType "application/json" -TimeoutSec 5 -ErrorAction Stop
                    $httpStatus = "HTTP 200 (GraphQL OK)"
                } else {
                    $testPath = switch ($item.name) {
                        "frontend" { "/healthz" }
                        "keycloak" { "/realms/microservices-realm" }
                        default    { "/" }
                    }
                    $res = Invoke-WebRequest -Uri "$($item.url)$testPath" -TimeoutSec 5 -UseBasicParsing -ErrorAction Stop
                    $httpStatus = "HTTP $($res.StatusCode)"
                }
            } catch {
                if ($_.Exception.Response) {
                    $httpStatus = "HTTP $($_.Exception.Response.StatusCode.value__)"
                } else {
                    $httpStatus = "Fail: $($_.Exception.Message)"
                }
            }
        }

        $table += [pscustomobject]@{
            Service    = $item.name
            LocalPort  = $item.port
            PID        = $item.pid
            Status     = if ($isRunning) { "RUNNING" } else { "STOPPED" }
            EdgeHealth = $httpStatus
            PublicUrl  = $item.url
        }
    }

    $table | Format-Table -AutoSize
}

function Start-AllTunnels {
    Show-Header "Starting Cloudflare Quick Tunnels for DevSecOps"

    $cfCmd = Get-Command "cloudflared" -ErrorAction SilentlyContinue
    if (-not $cfCmd) {
        throw "cloudflared CLI was not found in PATH. Install with 'winget install Cloudflare.cloudflared' or from https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/downloads/"
    }

    # Pre-flight check: ensure local services are listening
    $targets = @(
        @{ Name = "frontend"; Port = 5173; HealthPath = "/healthz"; Desc = "Novashop Storefront" },
        @{ Name = "router";   Port = 8080; HealthPath = "";         Desc = "Cosmo Router Supergraph" },
        @{ Name = "keycloak"; Port = 8181; HealthPath = "/realms/microservices-realm"; Desc = "Keycloak IAM" }
    )

    Write-Host "Verifying local service readiness..." -ForegroundColor Cyan
    foreach ($t in $targets) {
        try {
            $tcp = New-Object System.Net.Sockets.TcpClient
            $tcp.Connect("127.0.0.1", $t.Port)
            $tcp.Close()
            Write-Host "  [OK] $($t.Desc) is listening on port $($t.Port)" -ForegroundColor Green
        } catch {
            Write-Host "  [!] WARNING: Port $($t.Port) ($($t.Desc)) is not listening locally! Post-deploy tests may fail." -ForegroundColor Yellow
        }
    }

    # Stop any previous tunnels
    Stop-AllTunnels -DisableInGitHub $false

    $activeProcesses = @()
    foreach ($t in $targets) {
        $logPath = Join-Path $logDir "tunnel-$($t.Name).log"
        if (Test-Path $logPath) { Remove-Item $logPath -Force }

        Write-Host "  ▶ Spawning tunnel for $($t.Desc) (http://localhost:$($t.Port))..." -ForegroundColor Cyan
        $argList = @(
            "tunnel",
            "--protocol", "http2",
            "--url", "http://localhost:$($t.Port)",
            "--logfile", $logPath,
            "--loglevel", "info",
            "--no-autoupdate"
        )
        $proc = Start-Process -FilePath $cfCmd.Source -ArgumentList $argList -PassThru -NoNewWindow -RedirectStandardOutput (Join-Path $logDir "tunnel-$($t.Name).out") -RedirectStandardError (Join-Path $logDir "tunnel-$($t.Name).err")

        $activeProcesses += [ordered]@{
            name    = $t.Name
            desc    = $t.Desc
            port    = $t.Port
            pid     = $proc.Id
            process = $proc
            logPath = $logPath
            url     = ""
        }
    }

    # Capture URLs from log files
    Write-Host "`nWaiting for Cloudflare Quick Tunnel assignment (up to 40s)..." -ForegroundColor Cyan
    $timeout = [DateTime]::UtcNow.AddSeconds(40)
    while ([DateTime]::UtcNow -lt $timeout) {
        $allFound = $true
        foreach ($item in $activeProcesses) {
            if (-not $item.url) {
                $allFound = $false
                $pathsToCheck = @($item.logPath, (Join-Path $logDir "tunnel-$($item.name).out"), (Join-Path $logDir "tunnel-$($item.name).err"))
                foreach ($p in $pathsToCheck) {
                    if (Test-Path $p) {
                        try {
                            $content = Get-Content $p -Raw -ErrorAction SilentlyContinue
                            if ($content -and $content -match "https://[a-zA-Z0-9-]+\.trycloudflare\.com") {
                                $item.url = $matches[0]
                                Write-Host "  [OK] $($item.desc) -> $($item.url)" -ForegroundColor Green
                                break
                            }
                        } catch {}
                    }
                }
            }
        }
        if ($allFound) { break }
        Start-Sleep -Milliseconds 400
    }

    # Verify that all URLs were assigned
    $missing = $activeProcesses | Where-Object { -not $_.url }
    if ($missing) {
        Write-Host "`n[!] Some tunnels failed to obtain a trycloudflare.com URL:" -ForegroundColor Red
        foreach ($m in $missing) {
            Write-Host "  - $($m.name) (Check logs in: $logDir)" -ForegroundColor Yellow
        }
        throw "Failed to initialize all Cloudflare tunnels."
    }

    # Edge propagation wait
    Write-Host "`nWaiting 10s for Cloudflare Anycast edge DNS propagation..." -ForegroundColor Cyan
    Start-Sleep -Seconds 10

    # Validate reachability
    Write-Host "Testing edge reachability over public internet..." -ForegroundColor Cyan
    foreach ($item in $activeProcesses) {
        $checkUrl = switch ($item.name) {
            "frontend" { "$($item.url)/healthz" }
            "router"   { "$($item.url)/graphql" }
            "keycloak" { "$($item.url)/realms/microservices-realm" }
            default    { $item.url }
        }

        $reachable = $false
        for ($attempt = 1; $attempt -le 5; $attempt++) {
            try {
                if ($item.name -eq "router") {
                    $res = Invoke-RestMethod -Uri $checkUrl -Method Post -Body '{"query":"{ __typename }"}' -ContentType "application/json" -TimeoutSec 10
                    if ($res.data.__typename) { $reachable = $true; break }
                } else {
                    $res = Invoke-WebRequest -Uri $checkUrl -TimeoutSec 10 -UseBasicParsing
                    if ($res.StatusCode -eq 200) { $reachable = $true; break }
                }
            } catch {
                Start-Sleep -Seconds 3
            }
        }

        if ($reachable) {
            Write-Host "  [OK] $($item.name) is reachable at: $($item.url)" -ForegroundColor Green
        } else {
            Write-Host "  [!] WARNING: $($item.name) did not respond with HTTP 200 yet ($checkUrl). It may still be propagating." -ForegroundColor Yellow
        }
    }

    # Save state to file
    $stateData = [ordered]@{
        startedAt = (Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ")
        processes = @(
            foreach ($item in $activeProcesses) {
                [ordered]@{
                    name = $item.name
                    port = $item.port
                    pid  = $item.pid
                    url  = $item.url
                    log  = $item.logPath
                }
            }
        )
    }
    $stateData | ConvertTo-Json -Depth 5 | Set-Content -Path $stateFile -Encoding UTF8

    # Extract target URLs
    $frontendUrl = ($activeProcesses | Where-Object { $_.name -eq "frontend" }).url
    $routerUrl   = ($activeProcesses | Where-Object { $_.name -eq "router" }).url
    $keycloakUrl = ($activeProcesses | Where-Object { $_.name -eq "keycloak" }).url

    # Update GitHub Actions variables if requested
    if ($UpdateGitHub) {
        Write-Host "`nUpdating GitHub Actions repository variables ($Repo)..." -ForegroundColor Cyan
        & gh variable set DEVSECOPS_POST_DEPLOY_ENABLED --body "true" -R $Repo
        & gh variable set DEVSECOPS_BASE_URL --body "$frontendUrl" -R $Repo
        & gh variable set DEVSECOPS_FRONTEND_URL --body "$frontendUrl" -R $Repo
        & gh variable set DEVSECOPS_KEYCLOAK_URL --body "$keycloakUrl" -R $Repo

        Write-Host "  [OK] DEVSECOPS_POST_DEPLOY_ENABLED = true" -ForegroundColor Green
        Write-Host "  [OK] DEVSECOPS_BASE_URL            = $frontendUrl" -ForegroundColor Green
        Write-Host "  [OK] DEVSECOPS_FRONTEND_URL        = $frontendUrl" -ForegroundColor Green
        Write-Host "  [OK] DEVSECOPS_KEYCLOAK_URL        = $keycloakUrl" -ForegroundColor Green
    }

    Write-Host ""
    Write-Host ("=" * 80) -ForegroundColor Cyan
    Write-Host " 🌐 PUBLIC CLOUDFLARE ENDPOINTS (EXPOSED FOR DEVSECOPS & GITHUB ACTIONS)" -ForegroundColor Cyan
    Write-Host ("=" * 80) -ForegroundColor Cyan
    Write-Host "  ▶ Novashop Storefront (Frontend / DAST) : $frontendUrl" -ForegroundColor Green
    Write-Host "  ▶ Cosmo Router (GraphQL Supergraph)   : $routerUrl" -ForegroundColor Green
    Write-Host "  ▶ Keycloak IAM (OAuth2 / Realm)       : $keycloakUrl" -ForegroundColor Green
    Write-Host ("-" * 80) -ForegroundColor DarkGray
    Write-Host "  To stop the tunnels at any time, run: .\platform-minikube.ps1 cloudflare -Action stop`n" -ForegroundColor DarkGray
}

switch ($Action) {
    "Start"   { Start-AllTunnels }
    "Stop"    { Stop-AllTunnels -DisableInGitHub $UpdateGitHub }
    "Status"  { Get-TunnelStatus }
    "Restart" { Stop-AllTunnels -DisableInGitHub $false; Start-AllTunnels }
}
