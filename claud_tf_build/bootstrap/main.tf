terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.82.0"
    }
  }

  # Intentionally local — this config bootstraps the remote backend itself
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}

locals {
  # Include a truncated account ID to guarantee global bucket name uniqueness
  name_prefix = "${var.project}-${var.environment}"
}

data "aws_caller_identity" "current" {}

# ------------------------------------------------------------------
# KMS Customer-Managed Key — encrypts Terraform state at rest.
# Using a CMK instead of SSE-S3 gives per-access CloudTrail audit
# entries and the ability to revoke decryption independently of S3.
# ------------------------------------------------------------------

resource "aws_kms_key" "state" {
  description             = "CMK for ${local.name_prefix} Terraform state bucket"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  # Explicit key policy: root retains full admin (prevents lockout).
  # S3 is permitted to call GenerateDataKey/Decrypt on behalf of callers
  # whose IAM policies allow kms:GenerateDataKey on this key.
  # DynamoDB is permitted to use the key for table SSE.
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "EnableRootAdmin"
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root" }
        Action    = "kms:*"
        Resource  = "*"
      },
      {
        Sid    = "AllowS3StateEncryption"
        Effect = "Allow"
        Principal = { Service = "s3.amazonaws.com" }
        Action   = ["kms:Decrypt", "kms:GenerateDataKey"]
        Resource = "*"
        Condition = {
          StringEquals = { "kms:CallerAccount" = data.aws_caller_identity.current.account_id }
        }
      },
      {
        Sid    = "AllowDynamoDBEncryption"
        Effect = "Allow"
        Principal = { Service = "dynamodb.amazonaws.com" }
        Action   = ["kms:Decrypt", "kms:GenerateDataKey", "kms:DescribeKey", "kms:CreateGrant"]
        Resource = "*"
        Condition = {
          StringEquals = { "kms:CallerAccount" = data.aws_caller_identity.current.account_id }
        }
      },
    ]
  })

  lifecycle {
    prevent_destroy = true
  }

  tags = {
    Name = "${local.name_prefix}-tfstate-key"
  }
}

resource "aws_kms_alias" "state" {
  name          = "alias/${local.name_prefix}-tfstate"
  target_key_id = aws_kms_key.state.key_id
}

# ------------------------------------------------------------------
# S3 Bucket — Terraform state storage
# ------------------------------------------------------------------

resource "aws_s3_bucket" "state" {
  # Bucket names must be globally unique; suffix with account ID
  bucket = "${local.name_prefix}-tfstate-${data.aws_caller_identity.current.account_id}"

  # Object Lock must be enabled at bucket creation — cannot be added later.
  object_lock_enabled = true

  # Prevent accidental deletion of the bucket containing all state files
  lifecycle {
    prevent_destroy = true
  }

  tags = {
    Name = "${local.name_prefix}-tfstate"
  }
}

resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id

  versioning_configuration {
    status = "Enabled"
  }
}

# SSE-KMS: every state file object is encrypted under the CMK above.
# CloudTrail will record a KMS Decrypt call for every state read,
# giving a full audit trail of who accessed Terraform state and when.
resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.state.arn
    }
    # Reduce KMS API calls and cost via S3 Bucket Keys.
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket = aws_s3_bucket.state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  # Versioning is required for Object Lock; clean up old versions after 90 days.
  rule {
    id     = "expire-old-versions"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = 90
    }
  }
}

# Object Lock in GOVERNANCE mode: state file versions cannot be deleted
# during the retention period, even by privileged IAM users, without the
# s3:BypassGovernanceRetention permission (break-glass scenario only).
resource "aws_s3_bucket_object_lock_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    default_retention {
      mode = "GOVERNANCE"
      days = 90
    }
  }

  depends_on = [aws_s3_bucket_versioning.state]
}

# ------------------------------------------------------------------
# DynamoDB Table — Terraform state locking
# ------------------------------------------------------------------

resource "aws_dynamodb_table" "locks" {
  name         = "${local.name_prefix}-tf-locks"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  # Encrypt the lock table with the same CMK used for the state bucket.
  server_side_encryption {
    enabled     = true
    kms_key_arn = aws_kms_key.state.arn
  }

  # Protect the lock table from accidental deletion
  lifecycle {
    prevent_destroy = true
  }

  tags = {
    Name = "${local.name_prefix}-tf-locks"
  }
}
