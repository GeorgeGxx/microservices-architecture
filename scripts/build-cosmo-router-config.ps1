[CmdletBinding()]
param(
    [string]$RepositoryRoot = (Split-Path -Parent $PSScriptRoot),
    [switch]$SkipChartCopy
)

$ErrorActionPreference = 'Stop'
$configDir = Join-Path $RepositoryRoot 'cosmo-router'
$inputFile = Join-Path $configDir 'supergraph.yaml'
$outputFile = Join-Path $configDir 'execution-config.json'
$routerChartFiles = Join-Path $RepositoryRoot 'helm\charts\cosmo-router\files'

if (-not (Get-Command npx -ErrorAction SilentlyContinue)) {
    throw 'npx is required to compose Federation locally. Install Node.js (which includes npm/npx), then retry.'
}

Push-Location $RepositoryRoot
try {
    # Keep npm/wgc update notices and the repeated absolute paths out of the
    # normal platform bootstrap output. Preserve the complete diagnostics when
    # composition fails so Federation errors remain actionable.
    $composeOutput = @(& npx --yes wgc@0.132.0 router compose --input $inputFile --out $outputFile 2>&1)
    $composeExitCode = $LASTEXITCODE
    if ($composeExitCode -ne 0) {
        if ($composeOutput.Count -gt 0) {
            $composeOutput | ForEach-Object { Write-Host $_ }
        }
        throw "Cosmo local composition failed with exit code $composeExitCode. See the diagnostics above."
    }
}
finally {
    Pop-Location
}

if (-not (Test-Path -LiteralPath $outputFile) -or (Get-Item -LiteralPath $outputFile).Length -lt 100) {
    throw 'Cosmo composition did not produce a usable execution-config.json.'
}

try {
    $executionConfig = Get-Content -LiteralPath $outputFile -Raw | ConvertFrom-Json
} catch {
    throw "Cosmo produced invalid JSON at '$outputFile': $($_.Exception.Message)"
}

if (-not $SkipChartCopy) {
    New-Item -ItemType Directory -Path $routerChartFiles -Force | Out-Null
    Copy-Item -LiteralPath $outputFile -Destination (Join-Path $routerChartFiles 'execution-config.json') -Force
}

Write-Host "Cosmo Router execution config composed locally and saved to $outputFile"
if (-not $SkipChartCopy) {
    Write-Host "Generated execution config copied to $routerChartFiles for Helm/Argo CD"
}
