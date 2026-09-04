param (
    [Parameter(Mandatory = $false)]
    [string]$GcpRegion = "us-central1"
)

$ErrorActionPreference = "Stop"

$garRegistry = "$GcpRegion-docker.pkg.dev"
Write-Host "Authenticating Docker with Google Artifact Registry ($garRegistry)..." -ForegroundColor Cyan

gcloud auth configure-docker $garRegistry --quiet

if ($LASTEXITCODE -eq 0) {
    Write-Host "`n Successfully configured Docker authentication for Google Artifact Registry: $garRegistry" -ForegroundColor Green
} else {
    Write-Error "GCP Artifact Registry authentication failed. Ensure gcloud CLI is authenticated."
}
