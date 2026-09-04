param (
    [Parameter(Mandatory = $false)]
    [ValidateSet("aws", "azure", "gcp")]
    [string]$Cloud = "azure",

    [Parameter(Mandatory = $false)]
    [ValidateSet("dev", "staging", "prod")]
    [string]$Environment = "dev",

    [Parameter(Mandatory = $false)]
    [switch]$AutoApprove
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
    Write-Host " TERRAFORM APPLY - CLOUD: $($Cloud.ToUpper()) | ENV: $($Environment.ToUpper())" -ForegroundColor Cyan
    Write-Host " Directory: $tfDir" -ForegroundColor Cyan
    Write-Host "=======================================================`n" -ForegroundColor Cyan

    Write-Host "[1/2] Selecting workspace '$Environment'..." -ForegroundColor Yellow
    terraform workspace select $Environment

    $planFile = "$Environment.tfplan"
    Write-Host "`n[2/2] Applying Terraform plan ($planFile)..." -ForegroundColor Yellow
    if (Test-Path $planFile) {
        terraform apply $planFile
    } else {
        Write-Warning "Plan file '$planFile' not found. Running direct apply..."
        $varFile = "$Environment/terraform.tfvars"
        if ($AutoApprove) {
            if (Test-Path $varFile) {
                terraform apply -var-file=$varFile -auto-approve
            } else {
                terraform apply -auto-approve
            }
        } else {
            if (Test-Path $varFile) {
                terraform apply -var-file=$varFile
            } else {
                terraform apply
            }
        }
    }

    Write-Host "`n Infrastructure changes applied successfully for $Cloud ($Environment)." -ForegroundColor Green
}
finally {
    Pop-Location
}
