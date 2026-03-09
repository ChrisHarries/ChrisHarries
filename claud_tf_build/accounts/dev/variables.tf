variable "aws_region" {
  description = "AWS region to deploy resources into"
  type        = string
  default     = "eu-north-1"
}

variable "environment" {
  description = "Deployment environment (e.g. dev, staging, prod)"
  type        = string
}

variable "project" {
  description = "Project name, used as a prefix for resource naming"
  type        = string
}

# --- VPC ---

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.10.0.0/16"
}

variable "availability_zones" {
  description = "List of availability zones to deploy subnets into"
  type        = list(string)
  default     = ["eu-north-1a", "eu-north-1b", "eu-north-1c"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets (one per AZ)"
  type        = list(string)
  default     = ["10.10.1.0/24", "10.10.2.0/24", "10.10.3.0/24"]
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets (one per AZ)"
  type        = list(string)
  default     = ["10.10.101.0/24", "10.10.102.0/24", "10.10.103.0/24"]
}

# --- EKS ---

variable "cluster_version" {
  description = "Kubernetes version for the EKS cluster"
  type        = string
  default     = "1.32"
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

# --- Proxy ---

variable "proxy_instance_type" {
  description = "EC2 instance type for the Squid proxy"
  type        = string
  default     = "t4g.nano"
}

variable "proxy_squid_port" {
  description = "Port Squid listens on"
  type        = number
  default     = 3128
}

variable "proxy_allowed_domains" {
  description = "Domains allowed through the Squid proxy (supports leading-dot wildcards)"
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

# --- Datadog ---

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

variable "datadog_agent_chart_version" {
  description = "Version of the datadog/datadog Helm chart to deploy"
  type        = string
  default     = "3.88.0"
}

variable "datadog_monitor_notification_targets" {
  description = "Datadog notification handles for monitor alerts (e.g. '@slack-alerts', '@pagerduty-service')"
  type        = list(string)
  default     = []
}

# --- Database ---

variable "db_name" {
  description = "Initial database name"
  type        = string
  default     = "app"
}

variable "db_master_username" {
  description = "Master username for the Aurora cluster"
  type        = string
  default     = "dbadmin"
}

variable "db_engine_version" {
  description = "Aurora PostgreSQL engine version"
  type        = string
  default     = "17.4"
}

variable "db_instance_class" {
  description = "Instance class for Aurora. db.t4g.medium is the smallest supported Graviton instance."
  type        = string
  default     = "db.t4g.medium"
}

variable "db_backup_retention_days" {
  description = "Days to retain Aurora automated backups"
  type        = number
  default     = 7
}

variable "db_deletion_protection" {
  description = "Enable deletion protection on the Aurora cluster"
  type        = bool
  default     = false
}

variable "db_skip_final_snapshot" {
  description = "Skip final snapshot when the Aurora cluster is deleted"
  type        = bool
  default     = true
}

variable "db_reserved_instance_enabled" {
  description = "Purchase a reserved instance for the Aurora writer (set true to activate the commitment)"
  type        = bool
  default     = false
}

variable "db_reserved_instance_term" {
  description = "Reserved instance term in seconds: 31536000 (1yr) or 94608000 (3yr)"
  type        = number
  default     = 31536000
}

variable "db_reserved_instance_offering_type" {
  description = "Reserved instance payment option: 'No Upfront', 'Partial Upfront', or 'All Upfront'"
  type        = string
  default     = "No Upfront"
}

# --- Secret Rotation ---

variable "dd_key_rotation_days" {
  description = "Number of days between automatic Datadog API key rotations"
  type        = number
  default     = 30
}

# --- Node Groups ---

variable "node_groups" {
  description = "Map of managed node group configurations"
  type = map(object({
    instance_types = list(string)
    capacity_type  = string # ON_DEMAND or SPOT
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
  default = {
    general = {
      instance_types = ["t4g.medium"]
      capacity_type  = "ON_DEMAND"
      min_size       = 1
      max_size       = 3
      desired_size   = 2
      disk_size_gb   = 50
      labels         = { role = "general" }
      taints         = []
    }
  }
}
