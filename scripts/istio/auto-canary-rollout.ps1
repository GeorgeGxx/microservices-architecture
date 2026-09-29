[CmdletBinding()]
param(
    [ValidateSet("products-service")]
    [string]$Service = "products-service",
    [ValidatePattern('^[a-z0-9]([-a-z0-9]*[a-z0-9])?$')]
    [string]$Namespace = "dev",
    [ValidateRange(1, 3600)]
    [int]$StepIntervalSeconds = 30,
    [ValidateRange(1, 100)]
    [int[]]$Steps = @(10, 25, 50, 75, 100)
)

$ErrorActionPreference = "Stop"
$setWeights = Join-Path $PSScriptRoot "set-canary-weight.ps1"
if (-not (Test-Path $setWeights)) { throw "Missing canary weight controller: $setWeights" }
if (($Steps | Measure-Object -Minimum).Minimum -lt 1 -or ($Steps | Measure-Object -Maximum).Maximum -gt 100) {
    throw "Canary steps must be percentages between 1 and 100."
}
for ($index = 1; $index -lt $Steps.Count; $index++) {
    if ($Steps[$index] -le $Steps[$index - 1]) { throw "Canary steps must increase strictly (for example 10,25,50,75,100)." }
}
if ($Steps[-1] -ne 100) { throw "The final canary step must route 100% to v2 before promotion." }

$vsName = "$Service-canary-vs"
$currentJson = & kubectl get virtualservice $vsName -n $Namespace -o json 2>$null
if ($LASTEXITCODE -ne 0 -or -not $currentJson) { throw "Deploy the canary VirtualService before starting progressive rollout." }
$currentVs = ($currentJson -join "`n") | ConvertFrom-Json
$lastAcceptedV2 = [int]$currentVs.spec.http[1].route[1].weight

try {
    foreach ($v2 in $Steps) {
        $v1 = 100 - $v2
        Write-Host "`nSetting traffic to v1=$v1%, v2=$v2%..." -ForegroundColor Cyan
        & $setWeights -Service $Service -Namespace $Namespace -V1Weight $v1 -V2Weight $v2

        Start-Sleep -Seconds $StepIntervalSeconds
        & kubectl rollout status "deployment/$Service" -n $Namespace --timeout=60s
        if ($LASTEXITCODE -ne 0) { throw "Stable deployment readiness check failed at v2=$v2%." }
        & kubectl rollout status "deployment/$Service-v2" -n $Namespace --timeout=60s
        if ($LASTEXITCODE -ne 0) { throw "Canary deployment readiness check failed at v2=$v2%." }

        Write-Host "Observe product-service errors, latency and business behavior in Grafana/Kiali." -ForegroundColor Yellow
        $approval = Read-Host "Keep v2 at $v2% and advance to the next step? Enter Y to continue; anything else rolls traffic back"
        if ($approval -notmatch '^(y|yes)$') {
            & $setWeights -Service $Service -Namespace $Namespace -V1Weight (100 - $lastAcceptedV2) -V2Weight $lastAcceptedV2
            Write-Host "Promotion stopped. Traffic restored to the last accepted split (v1=$(100 - $lastAcceptedV2)%, v2=$lastAcceptedV2%)." -ForegroundColor Yellow
            return
        }
        $lastAcceptedV2 = $v2
    }
} catch {
    Write-Host "Canary gate failed: $($_.Exception.Message)" -ForegroundColor Red
    & $setWeights -Service $Service -Namespace $Namespace -V1Weight (100 - $lastAcceptedV2) -V2Weight $lastAcceptedV2
    throw
}

Write-Host "`nv2 now receives 100% of service traffic; v1 remains deployed and Ready for rollback." -ForegroundColor Green
Write-Host "To retire the old v1 image, promote the same immutable image tag through helm/values/values-minikube.yaml and let ArgoCD sync before deleting the canary workload." -ForegroundColor Yellow
