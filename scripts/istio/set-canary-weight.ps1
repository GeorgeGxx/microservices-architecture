[CmdletBinding()]
param(
    [ValidateSet("products-service")]
    [string]$Service = "products-service",
    [ValidatePattern('^[a-z0-9]([-a-z0-9]*[a-z0-9])?$')]
    [string]$Namespace = "dev",
    [ValidateRange(0, 100)]
    [int]$V1Weight = 90,
    [ValidateRange(0, 100)]
    [int]$V2Weight = 10
)

$ErrorActionPreference = "Stop"
if ($V1Weight + $V2Weight -ne 100) {
    throw "V1Weight and V2Weight must add up to 100."
}

function Get-ReadyReplicas {
    param([string]$Deployment)
    $json = & kubectl get deployment $Deployment -n $Namespace -o json 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $json) { return 0 }
    $object = ($json -join "`n") | ConvertFrom-Json
    if ($null -eq $object.status.readyReplicas) { return 0 }
    return [int]$object.status.readyReplicas
}

$vsName = "$Service-canary-vs"
$vsJson = & kubectl get virtualservice $vsName -n $Namespace -o json 2>$null
if ($LASTEXITCODE -ne 0 -or -not $vsJson) {
    throw "VirtualService '$vsName' does not exist in namespace '$Namespace'. Deploy the canary before changing weights."
}
$vs = ($vsJson -join "`n") | ConvertFrom-Json
if ($vs.spec.http.Count -lt 2 -or $vs.spec.http[1].route.Count -ne 2) {
    throw "VirtualService '$vsName' does not have the expected header route and two weighted destinations."
}

if ($V1Weight -gt 0 -and (Get-ReadyReplicas "$Service") -lt 1) {
    throw "Stable deployment '$Service' has no Ready replicas; refusing to send it traffic."
}
if ($V2Weight -gt 0 -and (Get-ReadyReplicas "$Service-v2") -lt 1) {
    throw "Canary deployment '$Service-v2' has no Ready replicas; refusing to send it traffic."
}

$patch = @(
    @{ op = "replace"; path = "/spec/http/1/route/0/weight"; value = $V1Weight },
    @{ op = "replace"; path = "/spec/http/1/route/1/weight"; value = $V2Weight }
) | ConvertTo-Json -Compress
& kubectl patch virtualservice $vsName -n $Namespace --type=json -p $patch
if ($LASTEXITCODE -ne 0) { throw "Istio rejected the requested canary weights." }

$verifiedJson = & kubectl get virtualservice $vsName -n $Namespace -o json
if ($LASTEXITCODE -ne 0) { throw "Could not verify the applied canary weights." }
$verified = ($verifiedJson -join "`n") | ConvertFrom-Json
$actualV1 = [int]$verified.spec.http[1].route[0].weight
$actualV2 = [int]$verified.spec.http[1].route[1].weight
if ($actualV1 -ne $V1Weight -or $actualV2 -ne $V2Weight) {
    throw "Weight verification mismatch: requested $V1Weight/$V2Weight, found $actualV1/$actualV2."
}
Write-Host "Canary traffic for '$Service' in '$Namespace': v1=$actualV1%, v2=$actualV2%." -ForegroundColor Green
