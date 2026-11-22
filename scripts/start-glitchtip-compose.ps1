[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repositoryRoot = Split-Path -Parent $PSScriptRoot
$environmentFile = Join-Path $repositoryRoot '.env'
$temporaryEnvironmentFile = Join-Path $repositoryRoot '.env.glitchtip.tmp'
$composeArguments = @(
    'compose',
    '-f', 'compose.yaml',
    '-f', 'compose.glitchtip.yaml'
)
$glitchtipComposeArguments = $composeArguments + @('--profile', 'glitchtip')
$reportingServices = @(
    'demand-forecast-service',
    'inventory-service',
    'notification-service',
    'orders-service',
    'payments-service',
    'fulfillment-service',
    'analytics-service',
    'products-service',
    'ai-service'
)
$expectedDsnNames = @(
    'GLITCHTIP_DEMAND_FORECAST_DSN',
    'GLITCHTIP_INVENTORY_DSN',
    'GLITCHTIP_NOTIFICATION_DSN',
    'GLITCHTIP_ORDERS_DSN',
    'GLITCHTIP_PAYMENTS_DSN',
    'GLITCHTIP_FULFILLMENT_DSN',
    'GLITCHTIP_ANALYTICS_DSN',
    'GLITCHTIP_PRODUCTS_DSN',
    'GLITCHTIP_AI_DSN',
    'GLITCHTIP_FRONTEND_DSN'
)

if (-not (Test-Path -LiteralPath $environmentFile -PathType Leaf)) {
    throw 'The root .env file is required. Copy .env.example and configure the local GlitchTip passwords first.'
}

Push-Location $repositoryRoot
try {
    Write-Host 'Starting GlitchTip and its database...' -ForegroundColor Cyan
    $startArguments = $glitchtipComposeArguments + @('up', '-d', 'glitchtip', 'glitchtip-db')
    & docker @startArguments
    if ($LASTEXITCODE -ne 0) {
        throw 'Docker Compose could not start GlitchTip and its database.'
    }

    $healthy = $false
    for ($attempt = 0; $attempt -lt 90; $attempt++) {
        $health = & docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' glitchtip 2>$null
        if ($LASTEXITCODE -eq 0 -and $health.Trim() -eq 'healthy') {
            $healthy = $true
            break
        }
        Start-Sleep -Seconds 2
    }
    if (-not $healthy) {
        throw 'GlitchTip did not become healthy. Inspect its container logs before retrying.'
    }

    Write-Host 'Creating the development organization and service projects...' -ForegroundColor Cyan
    $provisionArguments = $glitchtipComposeArguments + @(
        'exec', '-T', 'glitchtip', 'python', '/code/glitchtip-provision-projects.py'
    )
    $provisionOutput = & docker @provisionArguments
    if ($LASTEXITCODE -ne 0) {
        throw 'GlitchTip project provisioning failed. Inspect the GlitchTip container logs.'
    }

    $jsonLine = $provisionOutput | Where-Object { $_ -like 'GLITCHTIP_DSNS_JSON=*' } | Select-Object -Last 1
    if (-not $jsonLine) {
        throw 'The GlitchTip provisioner did not return DSNs; the local .env file was not changed.'
    }
    $dsnMap = $jsonLine.Substring('GLITCHTIP_DSNS_JSON='.Length) | ConvertFrom-Json
    foreach ($dsnName in $expectedDsnNames) {
        $dsnValue = [string]$dsnMap.$dsnName
        $parsedDsn = $null
        if (-not $dsnValue -or -not [Uri]::TryCreate($dsnValue, [UriKind]::Absolute, [ref]$parsedDsn)) {
            throw "The provisioner returned an invalid or empty DSN for $dsnName; the local .env file was not changed."
        }
    }

    $environmentLines = [System.Collections.Generic.List[string]]::new()
    foreach ($line in [System.IO.File]::ReadAllLines($environmentFile)) {
        $environmentLines.Add($line)
    }

    $changedDsnNames = [System.Collections.Generic.List[string]]::new()
    foreach ($dsnName in $expectedDsnNames) {
        $dsnValue = [string]$dsnMap.$dsnName
        $matchingIndex = -1
        for ($index = 0; $index -lt $environmentLines.Count; $index++) {
            if ($environmentLines[$index] -match ('^\s*' + [Regex]::Escape($dsnName) + '\s*=')) {
                $matchingIndex = $index
                break
            }
        }

        $currentValue = if ($matchingIndex -ge 0) { ($environmentLines[$matchingIndex] -split '=', 2)[1].Trim().Trim('"').Trim("'") } else { '' }
        if ($currentValue -cne $dsnValue) {
            $changedDsnNames.Add($dsnName)
        }

        $environmentEntry = "$dsnName=$dsnValue"
        if ($matchingIndex -ge 0) {
            $environmentLines[$matchingIndex] = $environmentEntry
        } else {
            $environmentLines.Add($environmentEntry)
        }
    }

    if ($changedDsnNames.Count -gt 0) {
        [System.IO.File]::WriteAllLines($temporaryEnvironmentFile, $environmentLines, [System.Text.UTF8Encoding]::new($false))
        Move-Item -LiteralPath $temporaryEnvironmentFile -Destination $environmentFile -Force
    }

    if ($changedDsnNames -contains 'GLITCHTIP_FRONTEND_DSN') {
        Write-Host 'Rebuilding the frontend with its GlitchTip DSN...' -ForegroundColor Cyan
        $frontendBuildArguments = $composeArguments + @('build', 'frontend')
        & docker @frontendBuildArguments
        if ($LASTEXITCODE -ne 0) {
            throw 'The frontend could not be rebuilt with the provisioned GlitchTip DSN.'
        }
    }

    $changedBackendDsns = @($changedDsnNames | Where-Object { $_ -ne 'GLITCHTIP_FRONTEND_DSN' })
    if ($changedBackendDsns.Count -gt 0) {
        Write-Host "Applying updated DSNs to $($changedBackendDsns.Count) backend projects..." -ForegroundColor Cyan
        $backendArguments = $composeArguments + @('up', '-d') + $reportingServices
        & docker @backendArguments
        if ($LASTEXITCODE -ne 0) {
            throw 'Backend services could not be recreated with the provisioned GlitchTip DSNs.'
        }
    }

    if ($changedDsnNames -contains 'GLITCHTIP_FRONTEND_DSN') {
        $frontendUpArguments = $composeArguments + @('up', '-d', 'frontend')
        & docker @frontendUpArguments
        if ($LASTEXITCODE -ne 0) {
            throw 'The frontend could not be recreated with the provisioned GlitchTip DSN.'
        }
    }

    foreach ($service in @($reportingServices) + @('frontend')) {
        $healthy = $false
        for ($attempt = 0; $attempt -lt 90; $attempt++) {
            $health = & docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' $service 2>$null
            if ($LASTEXITCODE -eq 0 -and $health.Trim() -eq 'healthy') {
                $healthy = $true
                break
            }
            Start-Sleep -Seconds 2
        }
        if (-not $healthy) {
            throw "Service $service did not become healthy after applying its GlitchTip DSN."
        }
    }

    Write-Host 'GlitchTip is ready with one project per reporting service. DSNs were stored only in the ignored local .env file.' -ForegroundColor Green
    Write-Host 'Dashboard: http://localhost:8090' -ForegroundColor Green
} finally {
    if (Test-Path -LiteralPath $temporaryEnvironmentFile -PathType Leaf) {
        Remove-Item -LiteralPath $temporaryEnvironmentFile -Force
    }
    Pop-Location
}
