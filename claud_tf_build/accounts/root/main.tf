provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project   = var.project
      ManagedBy = "terraform"
    }
  }
}

# ------------------------------------------------------------------
# AWS Organizations
# ------------------------------------------------------------------

resource "aws_organizations_organization" "this" {
  # Enable consolidated billing and all AWS Organizations features
  feature_set = "ALL"

  # Delegate these services to the management account so they work
  # across all member accounts out of the box.
  aws_service_access_principals = [
    "cloudtrail.amazonaws.com",
    "config.amazonaws.com",
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
