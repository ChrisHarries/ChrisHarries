variable "name_prefix" {
  description = "Prefix for resource names"
  type        = string
}

variable "vpc_id" {
  description = "ID of the VPC where the rotation Lambda runs"
  type        = string
}

variable "subnet_ids" {
  description = "Private subnet IDs for the rotation Lambda (minimum 2 AZs)"
  type        = list(string)
}

variable "secret_arn" {
  description = "ARN of the Secrets Manager secret to rotate (Datadog API key secret)"
  type        = string
}

variable "rotation_days" {
  description = "Number of days between automatic rotations"
  type        = number
  default     = 30
}

variable "datadog_site" {
  description = "Datadog site URL (e.g. datadoghq.com or datadoghq.eu)"
  type        = string
  default     = "datadoghq.eu"
}

variable "dd_key_name_prefix" {
  description = "Prefix for the Datadog API key name created during rotation"
  type        = string
  default     = "rotated-key"
}
