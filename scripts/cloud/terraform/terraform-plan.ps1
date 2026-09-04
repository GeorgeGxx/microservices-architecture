param (
    [Parameter(Mandatory = $false)]
    [ValidateSet("aws", "azure", "gcp")]
    [string]$Cloud = "azure",

    [Parameter(Mandatory = $false)]
    [ValidateSet("dev", "staging", "prod")]
    [string]$Environment = "dev"
)

$ErrorActionPreference = "Stop"

$rootDir = (Get-Item $PSScriptRoot).Parent.Parent.Parent.FullName
$tfDir = Join-Path $rootDir "terraform\environments\$Cloud"

if (-not (Test-Path $tfDir)) {
    Write-Error "Terraform directory not found: $tfDir"
}

Push-Location $tfDir
try {
    Write-Host "=======================================================" -ForegroundColor Cyan
    Write-Host " TERRAFORM PLAN - CLOUD: $($Cloud.ToUpper()) | ENV: $($Environment.ToUpper())" -ForegroundColor Cyan
    Write-Host " Directory: $tfDir" -ForegroundColor Cyan
    Write-Host "=======================================================`n" -ForegroundColor Cyan

    Write-Host "[1/3] Initializing Terraform backend and providers..." -ForegroundColor Yellow
    terraform init -input=false

    Write-Host "`n[2/3] Selecting / Creating workspace '$Environment'..." -ForegroundColor Yellow
    $workspaces = terraform workspace list
    if ($workspaces -match "\b$Environment\b") {
        terraform workspace select $Environment
    } else {
        terraform workspace new $Environment
    }

    Write-Host "`n[3/3] Generating Terraform execution plan ($Environment.tfplan)..." -ForegroundColor Yellow
    $varFile = "$Environment/terraform.tfvars"
    if (Test-Path $varFile) {
        terraform plan -var-file=$varFile -out="$Environment.tfplan"
    } else {
        terraform plan -out="$Environment.tfplan"
    }

    Write-Host "`n Plan generated successfully: $tfDir\$Environment.tfplan" -ForegroundColor Green
}
finally {
    Pop-Location
}
