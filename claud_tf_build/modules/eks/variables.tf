variable "name_prefix" {
  description = "Prefix for resource names"
  type        = string
}

variable "cluster_version" {
  description = "Kubernetes version for the EKS cluster"
  type        = string
}

variable "vpc_id" {
  description = "ID of the VPC"
  type        = string
}

variable "subnet_ids" {
  description = "Subnet IDs for the EKS control plane (use private subnets)"
  type        = list(string)
}

variable "cluster_role_arn" {
  description = "IAM role ARN for the EKS cluster"
  type        = string
}

variable "cluster_security_group_id" {
  description = "Security group ID for the EKS cluster"
  type        = string
}

variable "cluster_endpoint_public_access" {
  description = "Whether to enable public access to the EKS API endpoint"
  type        = bool
  default     = true
}

variable "cluster_endpoint_public_access_cidrs" {
  description = "CIDR blocks allowed to reach the public EKS API endpoint"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "ip_family" {
  description = "IP family for pod and service addressing. 'ipv4' or 'ipv6'."
  type        = string
  default     = "ipv6"

  validation {
    condition     = contains(["ipv4", "ipv6"], var.ip_family)
    error_message = "ip_family must be 'ipv4' or 'ipv6'."
  }
}

variable "cluster_log_types" {
  description = "List of EKS control plane log types to enable"
  type        = list(string)
  default     = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
}

variable "log_retention_days" {
  description = "Number of days to retain EKS control plane logs in CloudWatch"
  type        = number
  default     = 30
}

variable "kms_key_id" {
  description = "ARN of the KMS CMK used to encrypt the EKS CloudWatch Logs log group. The key policy must grant logs.<region>.amazonaws.com permission to use the key."
  type        = string
  default     = null
}

# ------------------------------------------------------------------
# EKS Add-on versions
# Pin these explicitly so applies never surprise-upgrade an add-on.
# Check latest versions with:
#   aws eks describe-addon-versions --kubernetes-version 1.32 \
#     --addon-name <name> --query 'addons[].addonVersions[0].addonVersion'
# ------------------------------------------------------------------

variable "addon_version_coredns" {
  description = "Version of the coredns EKS add-on"
  type        = string
  default     = "v1.11.4-eksbuild.2"
}

variable "addon_version_kube_proxy" {
  description = "Version of the kube-proxy EKS add-on"
  type        = string
  default     = "v1.32.0-eksbuild.2"
}

variable "addon_version_vpc_cni" {
  description = "Version of the vpc-cni EKS add-on"
  type        = string
  default     = "v1.19.2-eksbuild.5"
}

variable "addon_version_pod_identity_agent" {
  description = "Version of the eks-pod-identity-agent EKS add-on"
  type        = string
  default     = "v1.3.4-eksbuild.1"
}
