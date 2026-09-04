param (
    [Parameter(Mandatory = $false)]
    [string]$AwsRegion = "us-east-1",

    [Parameter(Mandatory = $false)]
    [string]$AccountId
)

$ErrorActionPreference = "Stop"

if (-not $AccountId) {
    Write-Host "Fetching AWS Account ID from current STS caller identity..." -ForegroundColor Cyan
    $AccountId = (aws sts get-caller-identity --query "Account" --output text 2>$null)
    if (-not $AccountId) {
        Write-Error "Could not determine AWS Account ID. Please ensure AWS CLI is configured or pass -AccountId."
    }
}

$ecrRegistry = "$AccountId.dkr.ecr.$AwsRegion.amazonaws.com"
Write-Host "Authenticating Docker with Amazon ECR ($ecrRegistry)..." -ForegroundColor Cyan

aws ecr get-login-password --region $AwsRegion | docker login --username AWS --password-stdin $ecrRegistry

if ($LASTEXITCODE -eq 0) {
    Write-Host "`n Successfully authenticated with Amazon ECR: $ecrRegistry" -ForegroundColor Green
} else {
    Write-Error "Amazon ECR authentication failed. Verify AWS credentials and permissions."
}
