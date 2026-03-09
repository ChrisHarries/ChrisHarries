variable "name_prefix" {
  description = "Prefix for resource names"
  type        = string
}

variable "kms_key_id" {
  description = "ARN of the KMS CMK used to encrypt Datadog secrets in Secrets Manager. Defaults to the AWS-managed key if not set."
  type        = string
  default     = null
}

variable "datadog_api_key" {
  description = "Datadog API key — stored in Secrets Manager and used by the agent"
  type        = string
  sensitive   = true
}

variable "datadog_app_key" {
  description = "Datadog application key — stored in Secrets Manager; required to manage API keys during rotation"
  type        = string
  sensitive   = true
}

variable "datadog_external_id" {
  description = "Datadog account/org external ID — used in the IAM cross-account trust policy. Found in the Datadog AWS integration page."
  type        = string
}

variable "eks_cluster_name" {
  description = "Name of the EKS cluster (used to scope monitors and log collection)"
  type        = string
}

variable "rds_cluster_id" {
  description = "ID of the Aurora cluster (used to scope RDS monitors)"
  type        = string
}

variable "cloudwatch_log_groups" {
  description = "CloudWatch log group ARNs to enable Datadog log collection on"
  type        = list(string)
  default     = []
}

variable "aws_services_enabled" {
  description = "AWS services to enable in the Datadog AWS integration"
  type        = list(string)
  default = [
    "cloudwatch",
    "ec2",
    "eks",
    "rds",
    "logs",
    "elasticloadbalancing",
    "autoscaling",
    "secretsmanager",
  ]
}

# --- Monitor thresholds ---

variable "node_cpu_critical" {
  description = "Node CPU % that triggers a CRITICAL monitor alert"
  type        = number
  default     = 90
}

variable "node_cpu_warning" {
  description = "Node CPU % that triggers a WARNING monitor alert"
  type        = number
  default     = 80
}

variable "node_memory_critical" {
  description = "Node memory % that triggers a CRITICAL monitor alert"
  type        = number
  default     = 90
}

variable "node_memory_warning" {
  description = "Node memory % that triggers a WARNING monitor alert"
  type        = number
  default     = 80
}

variable "pod_restart_critical" {
  description = "Pod restart count within the evaluation window that triggers CRITICAL"
  type        = number
  default     = 10
}

variable "pod_restart_warning" {
  description = "Pod restart count within the evaluation window that triggers WARNING"
  type        = number
  default     = 5
}

variable "aurora_cpu_critical" {
  description = "Aurora CPU % that triggers a CRITICAL monitor alert"
  type        = number
  default     = 85
}

variable "aurora_cpu_warning" {
  description = "Aurora CPU % that triggers a WARNING monitor alert"
  type        = number
  default     = 70
}

variable "aurora_connections_critical" {
  description = "Aurora connection count that triggers a CRITICAL monitor alert"
  type        = number
  default     = 80
}

variable "monitor_notification_targets" {
  description = "List of Datadog notification handles to alert (e.g. '@slack-alerts', '@pagerduty')"
  type        = list(string)
  default     = []
}
