<#
.SYNOPSIS
    Tags and pushes all Docker images to a Container Registry (Docker Hub, ACR, ECR).
.DESCRIPTION
    Usage: .\scripts\push-all.ps1 -Registry "your_dockerhub_user" [-Tag "1.0.0"]
#>
param (
    [Parameter(Mandatory = $true)]
    [string]$Registry,

    [Parameter(Mandatory = $false)]
    [string]$Tag = "1.0.0"
)

$ErrorActionPreference = "Stop"
$services = @("api-gateway", "inventory-service", "notification-service", "orders-service", "products-service", "frontend")

Write-Host "`n🚀 Pushing images to registry '$Registry' with tag '$Tag'..." -ForegroundColor Cyan

foreach ($svc in $services) {
    # Detect local image naming convention (standard: georgegxx/<svc>:<tag> or <svc>:<tag>)
    $sourceImage = "georgegxx/${svc}:${Tag}"
    $check = docker images -q $sourceImage 2>$null
    if (-not $check) {
        $sourceImage = "${svc}:${Tag}"
    }

    $remoteImage = "$Registry/${svc}:$Tag"
    Write-Host "  📦 Tagging $sourceImage -> $remoteImage" -ForegroundColor Yellow
    docker tag $sourceImage $remoteImage
    
    Write-Host "  ⬆️ Pushing $remoteImage..." -ForegroundColor Green
    docker push $remoteImage
}

Write-Host "`n✨ All images have been pushed successfully to the remote registry!" -ForegroundColor Cyan
