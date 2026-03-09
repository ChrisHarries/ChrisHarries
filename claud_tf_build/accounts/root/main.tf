provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project   = var.project
      ManagedBy = "terraform"
    }
  }
}

data "aws_caller_identity" "current" {}

# ------------------------------------------------------------------
# AWS Organizations
# ------------------------------------------------------------------

resource "aws_organizations_organization" "this" {
  # Enable consolidated billing and all AWS Organizations features
  feature_set = "ALL"

  # Delegate these services to the management account so they work
  # across all member accounts out of the box.
  aws_service_access_principals = [
    "access-analyzer.amazonaws.com",
    "cloudtrail.amazonaws.com",
    "config.amazonaws.com",
    "guardduty.amazonaws.com",
    "inspector2.amazonaws.com",
    "macie.amazonaws.com",
    "sso.amazonaws.com",
  ]
}

# ------------------------------------------------------------------
# Organizational Units
# ------------------------------------------------------------------

resource "aws_organizations_organizational_unit" "workloads" {
  name      = "Workloads"
  parent_id = aws_organizations_organization.this.roots[0].id
}

resource "aws_organizations_organizational_unit" "security" {
  name      = "Security"
  parent_id = aws_organizations_organization.this.roots[0].id
}

resource "aws_organizations_organizational_unit" "production" {
  name      = "Production"
  parent_id = aws_organizations_organizational_unit.workloads.id
}

resource "aws_organizations_organizational_unit" "development" {
  name      = "Development"
  parent_id = aws_organizations_organizational_unit.workloads.id
}

# ------------------------------------------------------------------
# Member accounts
# ------------------------------------------------------------------

resource "aws_organizations_account" "prod" {
  name      = "${var.project}-prod"
  email     = var.prod_account_email
  parent_id = aws_organizations_organizational_unit.production.id

  # Terraform will close (delete) the account on destroy. Set to false
  # to retain the account even when removed from state.
  close_on_deletion = true

  lifecycle {
    # Prevent accidental destruction of the production account.
    prevent_destroy = true
  }
}

resource "aws_organizations_account" "dev" {
  name      = "${var.project}-dev"
  email     = var.dev_account_email
  parent_id = aws_organizations_organizational_unit.development.id

  close_on_deletion = true
}

resource "aws_organizations_account" "security" {
  name      = "${var.project}-security"
  email     = var.security_account_email
  parent_id = aws_organizations_organizational_unit.security.id

  close_on_deletion = true

  lifecycle {
    prevent_destroy = true
  }
}

# ------------------------------------------------------------------
# Service Control Policies
# Applied to the Workloads OU so they govern both prod and dev.
# ------------------------------------------------------------------

# SCP 1: Prevent member accounts from leaving the organisation.
resource "aws_organizations_policy" "deny_leave_org" {
  name        = "DenyLeaveOrganization"
  description = "Prevents any principal in a member account from removing that account from the organisation."
  type        = "SERVICE_CONTROL_POLICY"

  content = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "DenyLeaveOrganization"
      Effect   = "Deny"
      Action   = "organizations:LeaveOrganization"
      Resource = "*"
    }]
  })
}

resource "aws_organizations_policy_attachment" "deny_leave_org" {
  policy_id = aws_organizations_policy.deny_leave_org.id
  target_id = aws_organizations_organizational_unit.workloads.id
}

# SCP 2: Prevent disabling or modifying CloudTrail.
resource "aws_organizations_policy" "deny_cloudtrail_changes" {
  name        = "DenyCloudTrailChanges"
  description = "Prevents deletion or disabling of CloudTrail trails so the audit log cannot be silenced."
  type        = "SERVICE_CONTROL_POLICY"

  content = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "DenyCloudTrailChanges"
      Effect = "Deny"
      Action = [
        "cloudtrail:DeleteTrail",
        "cloudtrail:StopLogging",
        "cloudtrail:UpdateTrail",
        "cloudtrail:PutEventSelectors",
      ]
      Resource = "*"
    }]
  })
}

resource "aws_organizations_policy_attachment" "deny_cloudtrail_changes" {
  policy_id = aws_organizations_policy.deny_cloudtrail_changes.id
  target_id = aws_organizations_organizational_unit.workloads.id
}

# SCP 3: Restrict workloads to the approved region.
# Global services (IAM, STS, Route53, CloudFront, etc.) always use us-east-1
# internally — the NotAction list exempts them from the region restriction.
resource "aws_organizations_policy" "restrict_regions" {
  name        = "RestrictToApprovedRegions"
  description = "Denies resource creation outside eu-north-1. Global services are exempted."
  type        = "SERVICE_CONTROL_POLICY"

  content = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "DenyNonApprovedRegions"
      Effect = "Deny"
      NotAction = [
        "iam:*",
        "sts:*",
        "route53:*",
        "cloudfront:*",
        "waf:*",
        "budgets:*",
        "health:*",
        "support:*",
        "trustedadvisor:*",
        "organizations:*",
        "account:*",
      ]
      Resource = "*"
      Condition = {
        StringNotEquals = {
          "aws:RequestedRegion" = ["eu-north-1"]
        }
      }
    }]
  })
}

resource "aws_organizations_policy_attachment" "restrict_regions" {
  policy_id = aws_organizations_policy.restrict_regions.id
  target_id = aws_organizations_organizational_unit.workloads.id
}

# SCP 4: Deny creation of long-lived IAM users and access keys.
# All human access should go through AWS IAM Identity Center (SSO).
resource "aws_organizations_policy" "deny_iam_users" {
  name        = "DenyIAMUserCreation"
  description = "Prevents creation of IAM users and long-lived access keys. Use IAM Identity Center for human access."
  type        = "SERVICE_CONTROL_POLICY"

  content = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "DenyIAMUserCreation"
      Effect = "Deny"
      Action = [
        "iam:CreateUser",
        "iam:CreateAccessKey",
      ]
      Resource = "*"
    }]
  })
}

resource "aws_organizations_policy_attachment" "deny_iam_users" {
  policy_id = aws_organizations_policy.deny_iam_users.id
  target_id = aws_organizations_organizational_unit.workloads.id
}

# ------------------------------------------------------------------
# Security OU — SCPs
# Attach the two most critical SCPs to the Security OU as well.
# The security account must never leave the org or silence the trail.
# ------------------------------------------------------------------

resource "aws_organizations_policy_attachment" "deny_leave_org_security" {
  policy_id = aws_organizations_policy.deny_leave_org.id
  target_id = aws_organizations_organizational_unit.security.id
}

resource "aws_organizations_policy_attachment" "deny_cloudtrail_changes_security" {
  policy_id = aws_organizations_policy.deny_cloudtrail_changes.id
  target_id = aws_organizations_organizational_unit.security.id
}

# SCP 5: Prevent disabling security services in the Security account.
resource "aws_organizations_policy" "deny_disable_security_services" {
  name        = "DenyDisableSecurityServices"
  description = "Prevents any principal in the Security account from disabling GuardDuty, Macie, Inspector, or IAM Access Analyzer."
  type        = "SERVICE_CONTROL_POLICY"

  content = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "DenyDisableSecurityServices"
      Effect = "Deny"
      Action = [
        "guardduty:DeleteDetector",
        "guardduty:DisassociateFromMasterAccount",
        "guardduty:DisassociateMembers",
        "guardduty:StopMonitoringMembers",
        "inspector2:Disable",
        "inspector2:DisassociateMember",
        "macie2:DisableMacie",
        "macie2:DisassociateMember",
        "access-analyzer:DeleteAnalyzer",
      ]
      Resource = "*"
    }]
  })
}

resource "aws_organizations_policy_attachment" "deny_disable_security_services" {
  policy_id = aws_organizations_policy.deny_disable_security_services.id
  target_id = aws_organizations_organizational_unit.security.id
}

# ------------------------------------------------------------------
# Delegated Administrators — Security account
# These must be declared in the management account.
# ------------------------------------------------------------------

resource "aws_guardduty_organization_admin_account" "security" {
  admin_account_id = aws_organizations_account.security.id
  depends_on       = [aws_organizations_organization.this]
}

resource "aws_inspector2_delegated_admin_account" "security" {
  account_id = aws_organizations_account.security.id
  depends_on = [aws_organizations_organization.this]
}

# Enable Macie in the management account first, then delegate to security.
resource "aws_macie2_account" "this" {
  status = "ENABLED"
}

resource "aws_macie2_organization_admin_account" "security" {
  admin_account_id = aws_organizations_account.security.id
  depends_on       = [aws_macie2_account.this]
}

resource "aws_organizations_delegated_administrator" "access_analyzer" {
  account_id        = aws_organizations_account.security.id
  service_principal = "access-analyzer.amazonaws.com"
}

resource "aws_organizations_delegated_administrator" "config" {
  account_id        = aws_organizations_account.security.id
  service_principal = "config.amazonaws.com"
}

# ------------------------------------------------------------------
# Organisation-wide CloudTrail
# The trail must live in the management account (is_organization_trail
# requires management-account credentials). Logs are delivered to an
# S3 bucket owned by the security account (created in that stack).
#
# APPLY ORDER:
#   1. Apply this stack (creates Security account + delegated admins).
#   2. Run bootstrap/ targeting the security account.
#   3. Apply accounts/security/ (creates cloudtrail_log_bucket).
#   4. Set cloudtrail_log_bucket_name = <output> and re-apply this stack.
#
# The count guard lets the first apply succeed without the bucket.
# ------------------------------------------------------------------

resource "aws_kms_key" "cloudtrail" {
  description             = "CMK for ${var.project} organisation-wide CloudTrail"
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
        Sid    = "AllowCloudTrailEncrypt"
        Effect = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action   = ["kms:GenerateDataKey*", "kms:DescribeKey"]
        Resource = "*"
        Condition = {
          StringLike = {
            "kms:EncryptionContext:aws:cloudtrail:arn" = "arn:aws:cloudtrail:*:${data.aws_caller_identity.current.account_id}:trail/*"
          }
          StringEquals = {
            "aws:SourceArn" = "arn:aws:cloudtrail:${var.aws_region}:${data.aws_caller_identity.current.account_id}:trail/${var.project}-org-trail"
          }
        }
      },
      {
        Sid    = "AllowDecryptForAnalysis"
        Effect = "Allow"
        Principal = { AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root" }
        Action   = ["kms:Decrypt", "kms:ReEncryptFrom"]
        Resource = "*"
        Condition = {
          StringLike = {
            "kms:EncryptionContext:aws:cloudtrail:arn" = "arn:aws:cloudtrail:*:*:trail/*"
          }
        }
      },
    ]
  })

  lifecycle { prevent_destroy = true }

  tags = { Name = "${var.project}-cloudtrail-key" }
}

resource "aws_kms_alias" "cloudtrail" {
  name          = "alias/${var.project}-cloudtrail"
  target_key_id = aws_kms_key.cloudtrail.key_id
}

resource "aws_cloudtrail" "org" {
  count = var.cloudtrail_log_bucket_name != "" ? 1 : 0

  name                          = "${var.project}-org-trail"
  s3_bucket_name                = var.cloudtrail_log_bucket_name
  kms_key_id                    = aws_kms_key.cloudtrail.arn
  is_organization_trail         = true
  is_multi_region_trail         = true
  enable_log_file_validation    = true
  include_global_service_events = true

  event_selector {
    read_write_type           = "All"
    include_management_events = true
  }

  tags = { Name = "${var.project}-org-trail" }

  depends_on = [aws_organizations_organization.this]
}
