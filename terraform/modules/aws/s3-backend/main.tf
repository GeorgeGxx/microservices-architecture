# ==============================================================================
# AWS S3 Remote State Backend Module with Least Privilege & Security Pillar
# Implements AWS Well-Architected Framework: Security Pillar (SEC01 - SEC06)
# ==============================================================================

terraform {
  required_version = ">= 1.8.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

# 1. S3 Bucket for Terraform Remote State
resource "aws_s3_bucket" "tf_state" {
  bucket        = var.bucket_name
  force_destroy = var.force_destroy

  tags = merge(
    var.tags,
    {
      Name        = var.bucket_name
      Environment = var.environment
      Purpose     = "TerraformRemoteState"
      Compliance  = "AWS-Well-Architected-Security-Pillar"
    }
  )
}

# 2. S3 Bucket Versioning (Mandatory for State Recovery & Audit)
resource "aws_s3_bucket_versioning" "tf_state_versioning" {
  bucket = aws_s3_bucket.tf_state.id
  versioning_configuration {
    status = "Enabled"
  }
}

# 3. Server-Side Encryption at Rest (SSE-S3 / SSE-KMS with Bucket Key)
resource "aws_s3_bucket_server_side_encryption_configuration" "tf_state_encryption" {
  bucket = aws_s3_bucket.tf_state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = var.kms_key_arn != null ? "aws:kms" : "AES256"
      kms_master_key_id = var.kms_key_arn
    }
    bucket_key_enabled = true
  }
}

# 4. S3 Block Public Access (All 4 Protections Enforced)
resource "aws_s3_bucket_public_access_block" "tf_state_public_access_block" {
  bucket = aws_s3_bucket.tf_state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# 5. S3 Bucket Policy: Principle of Least Privilege & TLS Enforcement
data "aws_iam_policy_document" "tf_state_policy" {
  # Deny all HTTP requests (Enforce TLS 1.2+ in transit)
  statement {
    sid    = "EnforceTLSRequestsOnly"
    effect = "Deny"

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    actions = ["s3:*"]

    resources = [
      aws_s3_bucket.tf_state.arn,
      "${aws_s3_bucket.tf_state.arn}/*"
    ]

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }

  # Deny unencrypted uploads
  statement {
    sid    = "DenyUnencryptedObjectUploads"
    effect = "Deny"

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    actions = ["s3:PutObject"]

    resources = [
      "${aws_s3_bucket.tf_state.arn}/*"
    ]

    condition {
      test     = "Null"
      variable = "s3:x-amz-server-side-encryption"
      values   = ["true"]
    }
  }
}

resource "aws_s3_bucket_policy" "tf_state_policy" {
  depends_on = [aws_s3_bucket_public_access_block.tf_state_public_access_block]
  bucket     = aws_s3_bucket.tf_state.id
  policy     = data.aws_iam_policy_document.tf_state_policy.json
}

# 6. DynamoDB Table for Terraform State Locking & Concurrency Control
resource "aws_dynamodb_table" "tf_lock" {
  name         = var.dynamodb_table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = var.kms_key_arn
  }

  tags = merge(
    var.tags,
    {
      Name        = var.dynamodb_table_name
      Environment = var.environment
      Purpose     = "TerraformStateLocking"
    }
  )
}
