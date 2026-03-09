variable "name_prefix" {
  description = "Prefix for resource names"
  type        = string
}

variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "node_role_arn" {
  description = "IAM role ARN for the node groups"
  type        = string
}

variable "subnet_ids" {
  description = "Subnet IDs for the node groups (use private subnets)"
  type        = list(string)
}

variable "node_security_group_id" {
  description = "Security group ID to attach to node instances"
  type        = string
}

variable "kms_key_id" {
  description = "ARN of the KMS CMK used to encrypt node EBS volumes. Defaults to the AWS-managed key if not set."
  type        = string
  default     = null
}

variable "node_groups" {
  description = "Map of managed node group configurations"
  type = map(object({
    instance_types = list(string)
    capacity_type  = string
    min_size       = number
    max_size       = number
    desired_size   = number
    disk_size_gb   = number
    labels         = map(string)
    taints = list(object({
      key    = string
      value  = string
      effect = string
    }))
  }))
}
