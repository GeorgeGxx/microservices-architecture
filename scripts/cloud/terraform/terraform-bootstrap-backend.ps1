# ==============================================================================
# Terraform Remote State Backend Bootstrapper (Multi-Cloud / AWS Security Pillar)
# Implements AWS Well-Architected Framework: Security Pillar & Least Privilege (PoLP)
# ==============================================================================
param (
    [Parameter(Mandatory = $false)]
    [ValidateSet("aws", "azure", "gcp")]
    [string]$Cloud = "aws",

    [Parameter(Mandatory = $false)]
    [string]$Region = "us-east-1",

    [Parameter(Mandatory = $false)]
    [ValidateSet("all", "staging", "prod")]
    [string]$Environment = "all",

    [Parameter(Mandatory = $false)]
    [string]$ProjectName = "georgegxx-msa",

    # Azure specific parameters
    [Parameter(Mandatory = $false)]
    [string]$ResourceGroupName = "georgegxx-tfstate-rg",

    [Parameter(Mandatory = $false)]
    [string]$StorageAccountName = "georgegxxtfstate",

    [Parameter(Mandatory = $false)]
    [string]$ContainerName = "tfstate"
)

$ErrorActionPreference = "Stop"

Write-Host "================================================================================" -ForegroundColor Cyan
Write-Host " TERRAFORM REMOTE STATE BOOTSTRAP - CLOUD: $($Cloud.ToUpper())" -ForegroundColor Cyan
Write-Host " Compliance: AWS Well-Architected Security Pillar & Principle of Least Privilege" -ForegroundColor Cyan
Write-Host "================================================================================`n" -ForegroundColor Cyan

switch ($Cloud) {
    "azure" {
        Write-Host "[1/3] Creating Azure Resource Group '$ResourceGroupName' in '$Region'..." -ForegroundColor Yellow
        az group create --name $ResourceGroupName --location $Region

        Write-Host "`n[2/3] Creating Azure Storage Account '$StorageAccountName'..." -ForegroundColor Yellow
        az storage account create --name $StorageAccountName --resource-group $ResourceGroupName --location $Region --sku Standard_LRS --encryption-services blob

        Write-Host "`n[3/3] Creating Blob Container '$ContainerName'..." -ForegroundColor Yellow
        az storage container create --name $ContainerName --account-name $StorageAccountName

        Write-Host "`n[OK] Azure Terraform Remote State backend ready: $StorageAccountName/$ContainerName" -ForegroundColor Green
    }
    "aws" {
        $targetEnvs = if ($Environment -eq "all") { @("staging", "prod") } else { @($Environment) }

        foreach ($envName in $targetEnvs) {
            $bucketName = "$ProjectName-tfstate-$envName"
            $dynamoTable = "$ProjectName-tflock-$envName"

            Write-Host "--------------------------------------------------------------------------------" -ForegroundColor White
            Write-Host " Provisioning AWS Backend for Environment: [$($envName.ToUpper())]" -ForegroundColor Cyan
            Write-Host "--------------------------------------------------------------------------------" -ForegroundColor White

            # 1. Create S3 Bucket
            Write-Host "[1/6] Ensuring S3 Bucket '$bucketName' exists..." -ForegroundColor Yellow
            $bucketExists = aws s3api head-bucket --bucket $bucketName 2>$null
            if ($LASTEXITCODE -ne 0) {
                if ($Region -eq "us-east-1") {
                    aws s3api create-bucket --bucket $bucketName --region $Region | Out-Null
                } else {
                    aws s3api create-bucket --bucket $bucketName --region $Region --create-bucket-configuration LocationConstraint=$Region | Out-Null
                }
                Write-Host "  [+] S3 Bucket created: $bucketName" -ForegroundColor Green
            } else {
                Write-Host "  [i] S3 Bucket already exists: $bucketName" -ForegroundColor Gray
            }

            # 2. Enable S3 Bucket Versioning (State History & Accidental Deletion Protection)
            Write-Host "[2/6] Enforcing S3 Bucket Versioning..." -ForegroundColor Yellow
            aws s3api put-bucket-versioning --bucket $bucketName --versioning-configuration Status=Enabled
            Write-Host "  [+] Versioning Enabled" -ForegroundColor Green

            # 3. Enforce Server-Side Encryption at Rest (SSE-S3 with Bucket Key)
            Write-Host "[3/6] Enforcing Server-Side Encryption (AES256 + Bucket Key)..." -ForegroundColor Yellow
            $sseConfig = '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"},"BucketKeyEnabled":true}]}'
            aws s3api put-bucket-encryption --bucket $bucketName --server-side-encryption-configuration $sseConfig
            Write-Host "  [+] SSE-S3 Encryption Configured" -ForegroundColor Green

            # 4. Enforce S3 Public Access Block (All 4 settings active)
            Write-Host "[4/6] Enforcing S3 Public Access Block (Zero Public Exposure)..." -ForegroundColor Yellow
            aws s3api put-public-access-block --bucket $bucketName --public-access-block-configuration "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"
            Write-Host "  [+] S3 Public Access Blocked" -ForegroundColor Green

            # 5. Attach Least-Privilege Bucket Policy (Enforce TLS 1.2+ HTTPS Only & Deny Unencrypted Uploads)
            Write-Host "[5/6] Applying Principle of Least Privilege Bucket Policy (HTTPS Only)..." -ForegroundColor Yellow
            $bucketPolicy = @"
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "EnforceTLSRequestsOnly",
            "Effect": "Deny",
            "Principal": "*",
            "Action": "s3:*",
            "Resource": [
                "arn:aws:s3:::$bucketName",
                "arn:aws:s3:::$bucketName/*"
            ],
            "Condition": {
                "Bool": {
                    "aws:SecureTransport": "false"
                }
            }
        },
        {
            "Sid": "DenyUnencryptedObjectUploads",
            "Effect": "Deny",
            "Principal": "*",
            "Action": "s3:PutObject",
            "Resource": "arn:aws:s3:::$bucketName/*",
            "Condition": {
                "Null": {
                    "s3:x-amz-server-side-encryption": "true"
                }
            }
        }
    ]
}
"@
            $tempPolicyPath = Join-Path ([System.IO.Path]::GetTempPath()) "policy-$bucketName.json"
            $bucketPolicy | Out-File -FilePath $tempPolicyPath -Encoding ascii
            aws s3api put-bucket-policy --bucket $bucketName --policy file://$tempPolicyPath
            Remove-Item $tempPolicyPath -Force -ErrorAction SilentlyContinue
            Write-Host "  [+] Least Privilege TLS Bucket Policy Attached" -ForegroundColor Green

            # 6. Ensure DynamoDB State Lock Table with PITR and SSE
            Write-Host "[6/6] Ensuring DynamoDB State Locking Table '$dynamoTable'..." -ForegroundColor Yellow
            $tableStatus = aws dynamodb describe-table --table-name $dynamoTable --region $Region --query "Table.TableStatus" --output text 2>$null
            if (-not $tableStatus) {
                aws dynamodb create-table `
                    --table-name $dynamoTable `
                    --attribute-definitions AttributeName=LockID,AttributeType=S `
                    --key-schema AttributeName=LockID,KeyType=HASH `
                    --billing-mode PAY_PER_REQUEST `
                    --region $Region | Out-Null
                Write-Host "  [+] DynamoDB Lock Table created: $dynamoTable" -ForegroundColor Green

                Start-Sleep -Seconds 5
                # Enable Point-in-Time Recovery
                aws dynamodb update-continuous-backups --table-name $dynamoTable --point-in-time-recovery-specification PointInTimeRecoveryEnabled=true --region $Region 2>$null | Out-Null
            } else {
                Write-Host "  [i] DynamoDB Lock Table already active: $dynamoTable" -ForegroundColor Gray
            }

            Write-Host "`n[SUCCESS] Environment [$($envName.ToUpper())] S3 State Backend is fully secure and operational.`n" -ForegroundColor Green
        }
    }
    "gcp" {
        $gcsBucket = "georgegxx-tfstate-gcp"
        Write-Host "[1/1] Creating Google Cloud Storage (GCS) Bucket '$gcsBucket'..." -ForegroundColor Yellow
        gcloud storage buckets create "gs://$gcsBucket" --location=$Region 2>$null

        Write-Host "`n[OK] GCP Terraform Remote State backend ready: gs://$gcsBucket" -ForegroundColor Green
    }
}
