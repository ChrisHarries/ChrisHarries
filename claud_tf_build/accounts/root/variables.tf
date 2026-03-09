variable "aws_region" {
  description = "AWS region for the management account"
  type        = string
  default     = "eu-north-1"
}

variable "project" {
  description = "Project name used as a prefix for resource naming"
  type        = string
  default     = "claude-terraform"
}

variable "prod_account_email" {
  description = "Unique email address for the production member account (must not be used in any other AWS account)"
  type        = string
}

variable "dev_account_email" {
  description = "Unique email address for the development member account (must not be used in any other AWS account)"
  type        = string
}

variable "security_account_email" {
  description = "Unique email address for the security member account (must not be used in any other AWS account)"
  type        = string
}

variable "cloudtrail_log_bucket_name" {
  description = "Name of the S3 bucket in the security account that receives org-wide CloudTrail logs. Leave empty on the first apply (before the security stack has been applied). Set to the security stack's cloudtrail_log_bucket_name output on subsequent applies."
  type        = string
  default     = ""
}
