<#
.SYNOPSIS
    Automates public HTTPS tunnels for API Gateway and Keycloak using Cloudflare Tunnels (cloudflared).
.DESCRIPTION
    Exposes API Gateway (Port 8080) and Keycloak IAM (Port 8181) to the public internet
    using Cloudflare's global edge network (trycloudflare.com) with official TLS/SSL certificates.
    100% free, unlimited, zero antivirus false-positives, and no login required.
#>

[CmdletBinding()]
param(
    [switch]$UpdateFrontendEnv
)

Write-Host ""
Write-Host "=======================================================" -ForegroundColor Cyan
Write-Host " 🌐 CLOUDFLARE PUBLIC TUNNELS (ZERO-TRUST EDGE)" -ForegroundColor Cyan
Write-Host "=======================================================" -ForegroundColor Cyan
Write-Host ""

# 1. Locate cloudflared binary
$cfPath = $null
$possiblePaths = @(
    "cloudflared",
    "C:\Program Files (x86)\cloudflared\cloudflared.exe",
    "C:\Program Files\cloudflared\cloudflared.exe",
    "$env:LOCALAPPDATA\Microsoft\WinGet\Links\cloudflared.exe"
)

foreach ($p in $possiblePaths) {
    if (Get-Command $p -ErrorAction SilentlyContinue) {
        $cfPath = $p
        break
    }
    if (Test-Path $p) {
        $cfPath = $p
        break
    }
}

if (-not $cfPath) {
    Write-Host "❌ 'cloudflared' CLI was not found." -ForegroundColor Red
    Write-Host "👉 Installing via winget..." -ForegroundColor Yellow
    winget install Cloudflare.cloudflared --accept-source-agreements --accept-package-agreements
    $cfPath = "C:\Program Files (x86)\cloudflared\cloudflared.exe"
}

# 2. Kill any old cloudflared processes
Get-Process -Name "cloudflared" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

$logGateway = Join-Path $env:TEMP "cf-gateway.log"
$logKeycloak = Join-Path $env:TEMP "cf-keycloak.log"
Remove-Item -Path $logGateway, $logKeycloak -Force -ErrorAction SilentlyContinue

Write-Host "[1/3] Starting Cloudflare Tunnels for API Gateway (8080) & Keycloak (8181)..." -ForegroundColor Yellow

$procGateway = Start-Process -FilePath $cfPath -ArgumentList "tunnel", "--url", "http://localhost:8080", "--logfile", "$logGateway" -PassThru -WindowStyle Hidden
$procKeycloak = Start-Process -FilePath $cfPath -ArgumentList "tunnel", "--url", "http://localhost:8181", "--logfile", "$logKeycloak" -PassThru -WindowStyle Hidden

# 3. Wait and extract the public URLs from the logs
Write-Host "[2/3] Resolving Cloudflare Edge HTTPS endpoints..." -ForegroundColor Yellow

$gatewayUrl = ""
$keycloakUrl = ""
$retries = 0

while ($retries -lt 30) {
    Start-Sleep -Seconds 1
    
    if (-not $gatewayUrl -and (Test-Path $logGateway)) {
        $logContentGw = Get-Content $logGateway -Raw 2>$null
        if ($logContentGw -match 'https://[a-zA-Z0-9-]+\.trycloudflare\.com') {
            $gatewayUrl = $Matches[0]
        }
    }

    if (-not $keycloakUrl -and (Test-Path $logKeycloak)) {
        $logContentKc = Get-Content $logKeycloak -Raw 2>$null
        if ($logContentKc -match 'https://[a-zA-Z0-9-]+\.trycloudflare\.com') {
            $keycloakUrl = $Matches[0]
        }
    }

    if ($gatewayUrl -and $keycloakUrl) {
        break
    }
    $retries++
}

if (-not $gatewayUrl -or -not $keycloakUrl) {
    Write-Warning "Failed to extract Cloudflare URLs within timeout."
    if ($procGateway -and -not $procGateway.HasExited) { Stop-Process -Id $procGateway.Id -Force }
    if ($procKeycloak -and -not $procKeycloak.HasExited) { Stop-Process -Id $procKeycloak.Id -Force }
    return
}

Write-Host "[3/3] Public HTTPS Tunnels Active!" -ForegroundColor Green

Write-Host "`n=======================================================" -ForegroundColor Cyan
Write-Host " 🌐 PUBLIC CLOUDFLARE HTTPS ENDPOINTS" -ForegroundColor Cyan
Write-Host "=======================================================" -ForegroundColor Cyan
Write-Host "  🚪 API Gateway URL:   " -NoNewline -ForegroundColor White
Write-Host "$gatewayUrl" -ForegroundColor Green
Write-Host "  🔐 Keycloak IAM URL:  " -NoNewline -ForegroundColor White
Write-Host "$keycloakUrl" -ForegroundColor Green
Write-Host "=======================================================" -ForegroundColor Cyan

Write-Host "`n📋 CONFIGURATION FOR VERCEL / ANGULAR (environment.prod.ts):" -ForegroundColor Yellow
Write-Host @"
export const environment = {
  production: true,
  gatewayUrl: '$gatewayUrl',
  keycloak: {
    url: '$keycloakUrl',
    realm: 'microservices-realm',
    clientId: 'microservices_frontend'
  }
};
"@ -ForegroundColor White

if ($UpdateFrontendEnv) {
    $envProdFile = Join-Path $PSScriptRoot "..\..\..\frontend\src\environments\environment.prod.ts"
    $envDevFile = Join-Path $PSScriptRoot "..\..\..\frontend\src\environments\environment.ts"
    $newEnvContent = @"
export const environment = {
  production: true,
  gatewayUrl: '$gatewayUrl',
  keycloak: {
    url: '$keycloakUrl',
    realm: 'microservices-realm',
    clientId: 'microservices_frontend'
  }
};
"@
    Set-Content -Path $envProdFile -Value $newEnvContent -Encoding UTF8
    Set-Content -Path $envDevFile -Value $newEnvContent -Encoding UTF8
    Write-Host "`n✅ Updated frontend environment files with public Cloudflare URLs!" -ForegroundColor Green
}

Write-Host "`n🔐 KEYCLOAK OIDC REDIRECT URI REMINDER:" -ForegroundColor Magenta
Write-Host "Make sure your Keycloak client ('microservices_frontend') has your Vercel URL" -ForegroundColor Gray
Write-Host "(e.g. 'https://microstore-app.vercel.app/*') and 'https://*.trycloudflare.com/*' in 'Valid Redirect URIs' and 'Web Origins'." -ForegroundColor Gray

Write-Host "`n=======================================================" -ForegroundColor Cyan
Write-Host " Keep this window open. Press Enter or Ctrl+C to stop tunnels..." -ForegroundColor Magenta
Write-Host "=======================================================" -ForegroundColor Cyan

try {
    $null = Read-Host
} finally {
    Write-Host "`nTerminating Cloudflare tunnels..." -ForegroundColor Gray
    if ($procGateway -and -not $procGateway.HasExited) {
        Stop-Process -Id $procGateway.Id -Force -ErrorAction SilentlyContinue
    }
    if ($procKeycloak -and -not $procKeycloak.HasExited) {
        Stop-Process -Id $procKeycloak.Id -Force -ErrorAction SilentlyContinue
    }
    Remove-Item -Path $logGateway, $logKeycloak -Force -ErrorAction SilentlyContinue
    Write-Host "✅ Cloudflare tunnels closed successfully." -ForegroundColor Green
}
