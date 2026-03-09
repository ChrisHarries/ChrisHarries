variable "name_prefix" {
  description = "Prefix for resource names"
  type        = string
}

variable "kms_key_id" {
  description = "ARN of the KMS CMK used to encrypt Aurora storage and the managed master password secret. Defaults to the AWS-managed key if not set."
  type        = string
  default     = null
}

variable "vpc_id" {
  description = "ID of the VPC"
  type        = string
}

variable "subnet_ids" {
  description = "Private subnet IDs for the DB subnet group (minimum 2 AZs)"
  type        = list(string)
}

variable "allowed_source_security_group_id" {
  description = "Security group ID allowed to connect to the DB (e.g. node SG)"
  type        = string
}

variable "database_name" {
  description = "Name of the initial database to create"
  type        = string
  default     = "app"
}

variable "master_username" {
  description = "Master username for the Aurora cluster"
  type        = string
  default     = "dbadmin"
}

variable "engine_version" {
  description = "Aurora PostgreSQL engine version"
  type        = string
  default     = "16.4"
}

variable "instance_class" {
  description = "Instance class for Aurora cluster instances. db.t3.medium is the smallest Aurora PostgreSQL supports."
  type        = string
  default     = "db.t3.medium"
}

variable "backup_retention_days" {
  description = "Number of days to retain automated backups"
  type        = number
  default     = 7
}

variable "deletion_protection" {
  description = "Whether to enable deletion protection on the cluster"
  type        = bool
  default     = false
}

variable "skip_final_snapshot" {
  description = "Whether to skip the final snapshot when the cluster is deleted"
  type        = bool
  default     = true
}

variable "password_rotation_days" {
  description = "Number of days between automatic master password rotations (managed by AWS RDS)"
  type        = number
  default     = 30
}

variable "reserved_instance_enabled" {
  description = "Whether to purchase a reserved instance for the writer. Requires the offering to exist in the target region."
  type        = bool
  default     = false
}

variable "reserved_instance_term" {
  description = "Reservation term in seconds. 31536000 = 1 year, 94608000 = 3 years."
  type        = number
  default     = 31536000

  validation {
    condition     = contains([31536000, 94608000], var.reserved_instance_term)
    error_message = "reserved_instance_term must be 31536000 (1 year) or 94608000 (3 years)."
  }
}

variable "reserved_instance_offering_type" {
  description = "Payment option for the reserved instance: 'No Upfront', 'Partial Upfront', or 'All Upfront'."
  type        = string
  default     = "No Upfront"

  validation {
    condition     = contains(["No Upfront", "Partial Upfront", "All Upfront"], var.reserved_instance_offering_type)
    error_message = "reserved_instance_offering_type must be 'No Upfront', 'Partial Upfront', or 'All Upfront'."
  }
}
