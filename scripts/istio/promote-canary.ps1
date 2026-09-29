[CmdletBinding()]
param(
    [ValidateSet("dev")]
    [string]$Namespace = "dev",
    [switch]$RetireCanary
)

$ErrorActionPreference = "Stop"
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$valuesPath = Join-Path $projectRoot "helm\values\values-minikube.yaml"
$destinationRulesPath = Join-Path $projectRoot "k8s\istio\destination-rules-dev.yaml"

function Get-DeploymentObject {
    param([string]$Name)
    $json = & kubectl get deployment $Name -n $Namespace -o json
    if ($LASTEXITCODE -ne 0 -or -not $json) { throw "Could not read deployment '$Name' in '$Namespace'." }
    return (($json -join "`n") | ConvertFrom-Json)
}

$canary = Get-DeploymentObject "products-service-v2"
$canaryImage = [string]$canary.spec.template.spec.containers[0].image
if ($canaryImage -notmatch '^georgegxx/products-service:(?!canary$|latest$)([^\s]+)$') {
    throw "Canary image '$canaryImage' is not a distinct tagged products-service image."
}
if ([int]$canary.status.readyReplicas -lt 1) { throw "Canary deployment has no Ready replicas." }

if (-not $RetireCanary) {
    $vsJson = & kubectl get virtualservice products-service-canary-vs -n $Namespace -o json
    if ($LASTEXITCODE -ne 0 -or -not $vsJson) { throw "The canary VirtualService is missing; verify the 100% v2 rollout before promotion." }
    $vs = ($vsJson -join "`n") | ConvertFrom-Json
    $stableWeight = [int]$vs.spec.http[1].route[0].weight
    $canaryWeight = [int]$vs.spec.http[1].route[1].weight
    if ($stableWeight -ne 0 -or $canaryWeight -ne 100) {
        throw "Promotion requires traffic at v1=0%, v2=100%; current split is v1=$stableWeight%, v2=$canaryWeight%."
    }
    if (-not (Test-Path -LiteralPath $valuesPath)) { throw "Minikube Helm values file not found: $valuesPath" }

    $content = [System.IO.File]::ReadAllText($valuesPath)
    $pattern = '(?m)^(\s*image:\s*\{\s*repository:\s*georgegxx/products-service,\s*tag:\s*)"[^"]+"(\s*\})'
    $matches = [regex]::Matches($content, $pattern)
    if ($matches.Count -ne 1) { throw "Expected exactly one products-service image tag in '$valuesPath'; found $($matches.Count). No values were changed." }
    $replacement = '${1}"' + $canaryImage.Split(':')[-1] + '"${2}'
    $updated = [regex]::Replace($content, $pattern, $replacement, 1)
    if ($updated -eq $content) {
        Write-Host "Stable Helm values already use canary image $canaryImage." -ForegroundColor Green
    } else {
        [System.IO.File]::WriteAllText($valuesPath, $updated, [System.Text.UTF8Encoding]::new($false))
        Write-Host "Updated stable Helm values to ${canaryImage}: $valuesPath" -ForegroundColor Green
    }
    Write-Host "Review and commit/push this values change to the GitOps branch, then wait for ArgoCD and products-service Deployment to become Ready." -ForegroundColor Yellow
    Write-Host "After the stable Deployment runs the same image, retire v2 with: .\scripts\istio\promote-canary.ps1 -Namespace $Namespace -RetireCanary" -ForegroundColor Yellow
    return
}

$stable = Get-DeploymentObject "products-service"
$stableImage = [string]$stable.spec.template.spec.containers[0].image
if ($stableImage -ne $canaryImage) {
    throw "Refusing to retire canary: stable image '$stableImage' does not match candidate '$canaryImage'. Promote through GitOps and wait for rollout first."
}
if ([int]$stable.status.readyReplicas -lt 1) { throw "Refusing to retire canary: stable deployment has no Ready replicas." }
if (-not (Test-Path -LiteralPath $destinationRulesPath)) { throw "DestinationRule baseline not found: $destinationRulesPath" }

Write-Host "Stable Deployment is Ready on $stableImage. Removing canary routing, restoring baseline subsets, then deleting v2." -ForegroundColor Cyan
& kubectl delete virtualservice products-service-canary-vs -n $Namespace --ignore-not-found
if ($LASTEXITCODE -ne 0) { throw "Could not remove the canary VirtualService; canary Deployment was kept." }
& kubectl apply -f $destinationRulesPath -n $Namespace
if ($LASTEXITCODE -ne 0) { throw "Could not restore baseline DestinationRules; canary Deployment was kept." }
& kubectl delete deployment products-service-v2 -n $Namespace
if ($LASTEXITCODE -ne 0) { throw "Could not remove the products-service v2 Deployment." }
Write-Host "Canary retired. Stable products-service remains on the promoted image $canaryImage." -ForegroundColor Green
