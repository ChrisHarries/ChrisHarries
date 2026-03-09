variable "aws_region" {
  description = "AWS region for security account resources"
  type        = string
  default     = "eu-north-1"
}

variable "project" {
  description = "Project name, used as a prefix for resource naming"
  type        = string
  default     = "claude-terraform"
}

variable "root_account_id" {
  description = "AWS account ID of the management (root) account. Used in the CloudTrail log bucket policy to scope the CloudTrail service principal."
  type        = string
}

variable "org_id" {
  description = "AWS Organizations organisation ID (e.g. o-xxxxxxxxxx). Used to allow all member accounts to write CloudTrail logs under the org prefix."
  type        = string
}

variable "datadog_api_key" {
  description = "Datadog API key — set via TF_VAR_datadog_api_key environment variable, not in tfvars"
  type        = string
  sensitive   = true
}

variable "datadog_app_key" {
  description = "Datadog APP key — set via TF_VAR_datadog_app_key environment variable, not in tfvars"
  type        = string
  sensitive   = true
}

variable "datadog_external_id" {
  description = "Datadog org external ID used in the IAM cross-account trust policy"
  type        = string
  default     = "D474D06"
}

variable "datadog_site" {
  description = "Datadog site hostname (datadoghq.com for US, datadoghq.eu for EU)"
  type        = string
  default     = "datadoghq.eu"
}

variable "datadog_api_url" {
  description = "Datadog API base URL (matches site)"
  type        = string
  default     = "https://api.datadoghq.eu/"
}
