provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project   = var.project
      ManagedBy = "terraform"
      Stack     = "security"
    }
  }
}

provider "datadog" {
  api_key = var.datadog_api_key
  app_key = var.datadog_app_key
  api_url = var.datadog_api_url
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# ------------------------------------------------------------------
# KMS — single CMK for all security account encrypted resources
# Covers: S3 (CloudTrail log bucket), CloudWatch Logs, GuardDuty export
# ------------------------------------------------------------------

resource "aws_kms_key" "security" {
  description             = "CMK for ${var.project} security account resources"
  deletion_window_in_days = 7
  enable_key_rotation     = true

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
        Sid    = "AllowS3Encryption"
        Effect = "Allow"
        Principal = { Service = "s3.amazonaws.com" }
        Action   = ["kms:Decrypt", "kms:GenerateDataKey"]
        Resource = "*"
        Condition = {
          StringEquals = { "kms:CallerAccount" = data.aws_caller_identity.current.account_id }
        }
      },
      {
        Sid    = "AllowCloudWatchLogsEncryption"
        Effect = "Allow"
        Principal = { Service = "logs.${var.aws_region}.amazonaws.com" }
        Action   = ["kms:Encrypt*", "kms:Decrypt*", "kms:ReEncrypt*", "kms:GenerateDataKey*", "kms:Describe*"]
        Resource = "*"
        Condition = {
          ArnLike = {
            "kms:EncryptionContext:aws:logs:arn" = "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:*"
          }
        }
      },
    ]
  })

  lifecycle { prevent_destroy = true }

  tags = { Name = "${var.project}-security-key" }
}

resource "aws_kms_alias" "security" {
  name          = "alias/${var.project}-security"
  target_key_id = aws_kms_key.security.key_id
}

# ------------------------------------------------------------------
# S3 — CloudTrail log bucket
# Receives organisation-wide trail logs written by the management account.
# Object Lock (COMPLIANCE, 1 year) prevents deletion or overwrite.
# ------------------------------------------------------------------

resource "aws_s3_bucket" "cloudtrail_logs" {
  bucket = "${var.project}-cloudtrail-logs-${data.aws_caller_identity.current.account_id}"

  # Object Lock must be enabled at bucket creation; cannot be added later.
  object_lock_enabled = true

  lifecycle { prevent_destroy = true }

  tags = { Name = "${var.project}-cloudtrail-logs" }
}

resource "aws_s3_bucket_versioning" "cloudtrail_logs" {
  bucket = aws_s3_bucket.cloudtrail_logs.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_object_lock_configuration" "cloudtrail_logs" {
  bucket = aws_s3_bucket.cloudtrail_logs.id

  rule {
    default_retention {
      mode = "COMPLIANCE"
      days = 365
    }
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "cloudtrail_logs" {
  bucket = aws_s3_bucket.cloudtrail_logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.security.arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "cloudtrail_logs" {
  bucket                  = aws_s3_bucket.cloudtrail_logs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "cloudtrail_logs" {
  bucket = aws_s3_bucket.cloudtrail_logs.id

  rule {
    id     = "transition-to-glacier"
    status = "Enabled"

    transition {
      days          = 90
      storage_class = "GLACIER"
    }
  }
}

data "aws_iam_policy_document" "cloudtrail_bucket" {
  # CloudTrail: verify it has write access (called before first log delivery)
  statement {
    sid    = "AWSCloudTrailAclCheck"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
    actions   = ["s3:GetBucketAcl"]
    resources = [aws_s3_bucket.cloudtrail_logs.arn]
    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = ["arn:aws:cloudtrail:${var.aws_region}:${var.root_account_id}:trail/${var.project}-org-trail"]
    }
  }

  # CloudTrail: write logs for all org member accounts under the org prefix
  statement {
    sid    = "AWSCloudTrailWrite"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.cloudtrail_logs.arn}/AWSLogs/${var.org_id}/*"]
    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = ["arn:aws:cloudtrail:${var.aws_region}:${var.root_account_id}:trail/${var.project}-org-trail"]
    }
  }

  # Deny any non-HTTPS access
  statement {
    sid    = "DenyNonHTTPS"
    effect = "Deny"
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.cloudtrail_logs.arn, "${aws_s3_bucket.cloudtrail_logs.arn}/*"]
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "cloudtrail_logs" {
  bucket = aws_s3_bucket.cloudtrail_logs.id
  policy = data.aws_iam_policy_document.cloudtrail_bucket.json

  depends_on = [aws_s3_bucket_public_access_block.cloudtrail_logs]
}

# ------------------------------------------------------------------
# GuardDuty — org-wide threat detection
# This account is the delegated admin (registered in root/main.tf).
# ------------------------------------------------------------------

resource "aws_guardduty_detector" "this" {
  enable = true

  datasources {
    s3_logs { enable = true }
    kubernetes {
      audit_logs { enable = true }
    }
    malware_protection {
      scan_ec2_instance_with_findings {
        ebs_volumes { enable = true }
      }
    }
  }

  tags = { Name = "${var.project}-guardduty" }
}

resource "aws_guardduty_organization_configuration" "this" {
  auto_enable_organization_members = "ALL"
  detector_id                      = aws_guardduty_detector.this.id

  datasources {
    s3_logs { auto_enable = true }
    kubernetes {
      audit_logs { enable = true }
    }
    malware_protection {
      scan_ec2_instance_with_findings {
        ebs_volumes { auto_enable = true }
      }
    }
  }
}

# ------------------------------------------------------------------
# AWS Config — organisation-wide aggregator
# Collects configuration snapshots and compliance data from all accounts.
# ------------------------------------------------------------------

resource "aws_iam_role" "config_aggregator" {
  name = "${var.project}-security-config-aggregator"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowConfigService"
      Effect    = "Allow"
      Principal = { Service = "config.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = { Name = "${var.project}-config-aggregator" }
}

resource "aws_iam_role_policy_attachment" "config_aggregator" {
  role       = aws_iam_role.config_aggregator.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSConfigRoleForOrganizations"
}

resource "aws_config_configuration_aggregator" "org" {
  name = "${var.project}-org-aggregator"

  organization_aggregation_source {
    all_regions = true
    role_arn    = aws_iam_role.config_aggregator.arn
  }

  depends_on = [aws_iam_role_policy_attachment.config_aggregator]

  tags = { Name = "${var.project}-org-aggregator" }
}

# ------------------------------------------------------------------
# IAM Access Analyzer — organisation-wide
# Identifies resources shared outside the organisation or account.
# ------------------------------------------------------------------

resource "aws_accessanalyzer_analyzer" "org" {
  analyzer_name = "${var.project}-org-analyzer"
  type          = "ORGANIZATION"

  tags = { Name = "${var.project}-org-analyzer" }
}

# ------------------------------------------------------------------
# Amazon Inspector — vulnerability scanning across the org
# ------------------------------------------------------------------

resource "aws_inspector2_enabler" "this" {
  account_ids    = [data.aws_caller_identity.current.account_id]
  resource_types = ["EC2", "ECR", "LAMBDA"]
}

resource "aws_inspector2_organization_configuration" "this" {
  auto_enable {
    ec2    = true
    ecr    = true
    lambda = true
  }

  depends_on = [aws_inspector2_enabler.this]
}

# ------------------------------------------------------------------
# Amazon Macie — sensitive data discovery across the org
# ------------------------------------------------------------------

resource "aws_macie2_account" "this" {
  status = "ENABLED"
}

resource "aws_macie2_organization_configuration" "this" {
  auto_enable = true

  depends_on = [aws_macie2_account.this]
}

# ------------------------------------------------------------------
# CloudWatch Log Groups — security findings sink
# EventBridge rules pipe findings here; Datadog pulls via AWS integration.
# ------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "guardduty_findings" {
  name              = "/security/${var.project}/guardduty-findings"
  retention_in_days = 365
  kms_key_id        = aws_kms_key.security.arn

  tags = { Name = "${var.project}-guardduty-findings" }
}

resource "aws_cloudwatch_log_group" "inspector_findings" {
  name              = "/security/${var.project}/inspector-findings"
  retention_in_days = 365
  kms_key_id        = aws_kms_key.security.arn

  tags = { Name = "${var.project}-inspector-findings" }
}

resource "aws_cloudwatch_log_group" "macie_findings" {
  name              = "/security/${var.project}/macie-findings"
  retention_in_days = 365
  kms_key_id        = aws_kms_key.security.arn

  tags = { Name = "${var.project}-macie-findings" }
}

# Allow EventBridge to write to all three security log groups.
resource "aws_cloudwatch_log_resource_policy" "eventbridge_security" {
  policy_name = "${var.project}-security-eventbridge-logs"

  policy_document = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "AllowEventBridgePutLogs"
      Effect = "Allow"
      Principal = { Service = ["delivery.logs.amazonaws.com", "events.amazonaws.com"] }
      Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
      Resource = [
        "${aws_cloudwatch_log_group.guardduty_findings.arn}:*",
        "${aws_cloudwatch_log_group.inspector_findings.arn}:*",
        "${aws_cloudwatch_log_group.macie_findings.arn}:*",
      ]
    }]
  })
}

# ------------------------------------------------------------------
# EventBridge Rules — route security findings to CloudWatch Logs
# ------------------------------------------------------------------

# GuardDuty: HIGH (severity 7–8.9) and CRITICAL (severity 9+)
resource "aws_cloudwatch_event_rule" "guardduty_high" {
  name        = "${var.project}-guardduty-high-critical"
  description = "Capture GuardDuty findings with severity >= 7 (HIGH or CRITICAL)"

  event_pattern = jsonencode({
    source        = ["aws.guardduty"]
    "detail-type" = ["GuardDuty Finding"]
    detail = {
      severity = [{ numeric = [">=", 7] }]
    }
  })

  tags = { Name = "${var.project}-guardduty-high-critical" }
}

resource "aws_cloudwatch_event_target" "guardduty_high_to_logs" {
  rule      = aws_cloudwatch_event_rule.guardduty_high.name
  target_id = "GuardDutyHighToLogs"
  arn       = aws_cloudwatch_log_group.guardduty_findings.arn
}

# Inspector: CRITICAL findings (severity = CRITICAL)
resource "aws_cloudwatch_event_rule" "inspector_critical" {
  name        = "${var.project}-inspector-critical"
  description = "Capture Inspector2 findings with CRITICAL severity"

  event_pattern = jsonencode({
    source        = ["aws.inspector2"]
    "detail-type" = ["Inspector2 Finding"]
    detail = {
      severity = ["CRITICAL"]
    }
  })

  tags = { Name = "${var.project}-inspector-critical" }
}

resource "aws_cloudwatch_event_target" "inspector_critical_to_logs" {
  rule      = aws_cloudwatch_event_rule.inspector_critical.name
  target_id = "InspectorCriticalToLogs"
  arn       = aws_cloudwatch_log_group.inspector_findings.arn
}

# Macie: all sensitive data findings
resource "aws_cloudwatch_event_rule" "macie_findings" {
  name        = "${var.project}-macie-findings"
  description = "Capture all Macie sensitive data discovery findings"

  event_pattern = jsonencode({
    source        = ["aws.macie"]
    "detail-type" = ["Macie Finding"]
  })

  tags = { Name = "${var.project}-macie-findings" }
}

resource "aws_cloudwatch_event_target" "macie_findings_to_logs" {
  rule      = aws_cloudwatch_event_rule.macie_findings.name
  target_id = "MacieFindingsToLogs"
  arn       = aws_cloudwatch_log_group.macie_findings.arn
}

# ------------------------------------------------------------------
# Datadog Integration — security account
# Datadog pulls CloudWatch metrics and logs from this account.
# ------------------------------------------------------------------

data "aws_iam_policy_document" "datadog_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::464622532012:root"] # Datadog's AWS account
    }

    condition {
      test     = "StringEquals"
      variable = "sts:ExternalId"
      values   = [var.datadog_external_id]
    }
  }
}

resource "aws_iam_role" "datadog_integration" {
  name               = "${var.project}-security-datadog-integration"
  assume_role_policy = data.aws_iam_policy_document.datadog_assume_role.json

  tags = { Name = "${var.project}-security-datadog-integration" }
}

data "aws_iam_policy_document" "datadog_permissions" {
  statement {
    sid    = "DatadogCore"
    effect = "Allow"
    actions = [
      "cloudwatch:Get*",
      "cloudwatch:List*",
      "cloudwatch:Describe*",
      "logs:Get*",
      "logs:List*",
      "logs:Describe*",
      "logs:FilterLogEvents",
      "logs:StartQuery",
      "logs:StopQuery",
      "logs:GetQueryResults",
      "tag:GetResources",
      "tag:GetTagKeys",
      "tag:GetTagValues",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "DatadogGuardDuty"
    effect = "Allow"
    actions = [
      "guardduty:Get*",
      "guardduty:List*",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "DatadogSecurityHub"
    effect = "Allow"
    actions = [
      "config:Describe*",
      "config:Get*",
      "config:List*",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "datadog_permissions" {
  name   = "${var.project}-security-datadog-permissions"
  policy = data.aws_iam_policy_document.datadog_permissions.json

  tags = { Name = "${var.project}-security-datadog-permissions" }
}

resource "aws_iam_role_policy_attachment" "datadog_permissions" {
  role       = aws_iam_role.datadog_integration.name
  policy_arn = aws_iam_policy.datadog_permissions.arn
}

resource "datadog_integration_aws" "this" {
  account_id = data.aws_caller_identity.current.account_id
  role_name  = aws_iam_role.datadog_integration.name

  # Pull GuardDuty logs natively; Inspector/Macie findings arrive via the
  # /security/... CloudWatch Log Groups written by EventBridge above.
  account_specific_namespace_rules = {}

  depends_on = [aws_iam_role_policy_attachment.datadog_permissions]
}

resource "datadog_integration_aws_log_collection" "this" {
  account_id = data.aws_caller_identity.current.account_id
  services   = ["guardduty"]

  depends_on = [datadog_integration_aws.this]
}
