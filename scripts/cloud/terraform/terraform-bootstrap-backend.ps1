param (
    [Parameter(Mandatory = $false)]
    [ValidateSet("aws", "azure", "gcp")]
    [string]$Cloud = "azure",

    [Parameter(Mandatory = $false)]
    [string]$Region = "eastus",

    [Parameter(Mandatory = $false)]
    [string]$ResourceGroupName = "georgegxx-tfstate-rg",

    [Parameter(Mandatory = $false)]
    [string]$StorageAccountName = "georgegxxtfstate",

    [Parameter(Mandatory = $false)]
    [string]$ContainerName = "tfstate"
)

$ErrorActionPreference = "Stop"

Write-Host "=======================================================" -ForegroundColor Cyan
Write-Host " TERRAFORM REMOTE STATE BOOTSTRAP - CLOUD: $($Cloud.ToUpper())" -ForegroundColor Cyan
Write-Host "=======================================================`n" -ForegroundColor Cyan

switch ($Cloud) {
    "azure" {
        Write-Host "[1/3] Creating Azure Resource Group '$ResourceGroupName' in '$Region'..." -ForegroundColor Yellow
        az group create --name $ResourceGroupName --location $Region

        Write-Host "`n[2/3] Creating Azure Storage Account '$StorageAccountName'..." -ForegroundColor Yellow
        az storage account create --name $StorageAccountName --resource-group $ResourceGroupName --location $Region --sku Standard_LRS --encryption-services blob

        Write-Host "`n[3/3] Creating Blob Container '$ContainerName'..." -ForegroundColor Yellow
        az storage container create --name $ContainerName --account-name $StorageAccountName

        Write-Host "`n Azure Terraform Remote State backend ready: $StorageAccountName/$ContainerName" -ForegroundColor Green
    }
    "aws" {
        $bucketName = "georgegxx-tfstate-$Region"
        $dynamoTable = "terraform-state-locks"
        Write-Host "[1/2] Creating AWS S3 Bucket '$bucketName' in '$Region'..." -ForegroundColor Yellow
        aws s3api create-bucket --bucket $bucketName --region $Region

        Write-Host "`n[2/2] Creating DynamoDB Lock Table '$dynamoTable'..." -ForegroundColor Yellow
        aws dynamodb create-table --table-name $dynamoTable --attribute-definitions AttributeName=LockID,AttributeType=S --key-schema AttributeName=LockID,KeyType=HASH --billing-mode PAY_PER_REQUEST --region $Region 2>$null

        Write-Host "`n AWS Terraform Remote State backend ready: S3 Bucket ($bucketName) + DynamoDB ($dynamoTable)" -ForegroundColor Green
    }
    "gcp" {
        $gcsBucket = "georgegxx-tfstate-gcp"
        Write-Host "[1/1] Creating Google Cloud Storage (GCS) Bucket '$gcsBucket'..." -ForegroundColor Yellow
        gcloud storage buckets create "gs://$gcsBucket" --location=$Region 2>$null

        Write-Host "`n GCP Terraform Remote State backend ready: gs://$gcsBucket" -ForegroundColor Green
    }
}
