aws_region  = "eu-north-1"
environment = "prod"
project     = "claude-terraform"

vpc_cidr             = "10.20.0.0/16"
availability_zones   = ["eu-north-1a", "eu-north-1b", "eu-north-1c"]
private_subnet_cidrs = ["10.20.1.0/24", "10.20.2.0/24", "10.20.3.0/24"]
public_subnet_cidrs  = ["10.20.101.0/24", "10.20.102.0/24", "10.20.103.0/24"]

cluster_version                      = "1.30"
cluster_endpoint_public_access       = true
cluster_endpoint_public_access_cidrs = ["0.0.0.0/0"] # Restrict to office/VPN CIDR before go-live

proxy_instance_type = "t4g.nano"

db_instance_class        = "db.t4g.medium"
db_backup_retention_days = 14
db_deletion_protection   = true
db_skip_final_snapshot   = false

node_groups = {
  general = {
    instance_types = ["t4g.medium"]
    capacity_type  = "ON_DEMAND"
    min_size       = 2
    max_size       = 6
    desired_size   = 3
    disk_size_gb   = 100
    labels         = { role = "general" }
    taints         = []
  }
}
