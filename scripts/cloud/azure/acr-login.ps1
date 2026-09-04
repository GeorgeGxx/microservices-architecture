param (
    [Parameter(Mandatory = $true, HelpMessage = "Name of the Azure Container Registry (e.g. myacr)")]
    [string]$AcrName
)

$ErrorActionPreference = "Stop"

Write-Host "Authenticating Docker with Azure Container Registry: $AcrName..." -ForegroundColor Cyan
az acr login --name $AcrName

if ($LASTEXITCODE -eq 0) {
    Write-Host "Successfully authenticated with ACR: $AcrName.azurecr.io" -ForegroundColor Green
} else {
    Write-Error "ACR authentication failed. Make sure you are logged into Azure CLI (az login)."
}
