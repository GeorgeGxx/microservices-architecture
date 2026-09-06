<#
.SYNOPSIS
    Dynamically adjusts the Canary traffic weight between v1 and v2 for a given microservice.

.PARAMETER Service
    Name of the microservice (e.g., products-service, orders-service, inventory-service).

.PARAMETER WeightV1
    Percentage of traffic sent to v1 (Stable). Example: 90.

.PARAMETER WeightV2
    Percentage of traffic sent to v2 (Canary). Example: 10.

.PARAMETER Namespace
    Kubernetes namespace (default: "default").

.EXAMPLE
    .\set-canary-weight.ps1 -Service products-service -WeightV1 90 -WeightV2 10
    .\set-canary-weight.ps1 -Service orders-service -WeightV1 0 -WeightV2 100
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("products-service", "orders-service", "inventory-service", "notification-service")]
    [string]$Service,

    [Parameter(Mandatory=$true)]
    [ValidateRange(0, 100)]
    [int]$WeightV1,

    [Parameter(Mandatory=$true)]
    [ValidateRange(0, 100)]
    [int]$WeightV2,

    [string]$Namespace = "staging"
)

if (($WeightV1 + $WeightV2) -ne 100) {
    Write-Host "❌ Error: WeightV1 ($WeightV1%) + WeightV2 ($WeightV2%) must sum to exactly 100%." -ForegroundColor Red
    exit 1
}

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "   🔀 ISTIO CANARY TRAFFIC SHIFTER: $Service             " -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host " Target Service: $Service" -ForegroundColor Yellow
Write-Host " Distribution:   v1 (Stable) = $WeightV1% | v2 (Canary) = $WeightV2%" -ForegroundColor Yellow

$vsYaml = @"
apiVersion: networking.istio.io/v1alpha3
kind: VirtualService
metadata:
  name: $Service-vs
  namespace: $Namespace
spec:
  hosts:
    - $Service
  http:
    - match:
        - headers:
            x-canary:
              exact: "true"
      route:
        - destination:
            host: $Service
            subset: v2
    - route:
        - destination:
            host: $Service
            subset: v1
          weight: $WeightV1
        - destination:
            host: $Service
            subset: v2
          weight: $WeightV2
      timeout: 5s
      retries:
        attempts: 2
        perTryTimeout: 2s
        retryOn: "5xx,connect-failure,refused-stream"
"@

# Apply VirtualService dynamically
$tempFile = [System.IO.Path]::GetTempFileName() + ".yaml"
Set-Content -Path $tempFile -Value $vsYaml

try {
    kubectl apply -f $tempFile
    Write-Host "`n✅ VirtualService for '$Service' successfully updated!" -ForegroundColor Green
    Write-Host "Traffic is now routed $WeightV1% to v1 and $WeightV2% to v2." -ForegroundColor Green
} finally {
    Remove-Item -Path $tempFile -Force -ErrorAction SilentlyContinue
}

Write-Host "`nVerify live traffic shifts in Kiali: http://localhost:20001/kiali" -ForegroundColor Cyan
