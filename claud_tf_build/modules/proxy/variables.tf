variable "name_prefix" {
  description = "Prefix for resource names"
  type        = string
}

variable "vpc_id" {
  description = "ID of the VPC"
  type        = string
}

variable "subnet_id" {
  description = "Public subnet ID to place the proxy instance in"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type for the proxy (must be ARM/Graviton — AMI filter targets arm64)"
  type        = string
  default     = "t4g.nano"
}

variable "kms_key_id" {
  description = "ARN of the KMS CMK used to encrypt the proxy root EBS volume. Defaults to the AWS-managed key if not set."
  type        = string
  default     = null
}

variable "allowed_source_security_group_ids" {
  description = "Security group IDs allowed to send traffic through the proxy (e.g. node SG)"
  type        = list(string)
  default     = []
}

variable "allowed_source_cidrs" {
  description = "CIDR blocks allowed to send traffic through the proxy (fallback if not using SG references)"
  type        = list(string)
  default     = []
}

variable "squid_port" {
  description = "Port Squid listens on"
  type        = number
  default     = 3128
}

variable "allowed_domains" {
  description = "List of domains to allow through the proxy (supports wildcards, e.g. .example.com)"
  type        = list(string)
  default = [
    ".amazonaws.com",
    ".eks.amazonaws.com",
    ".ecr.io",
    "registry-1.docker.io",
    ".docker.io",
    ".docker.com",
    ".github.com",
    ".githubusercontent.com",
    ".quay.io",
  ]
}
