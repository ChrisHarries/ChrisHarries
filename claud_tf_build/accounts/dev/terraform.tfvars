aws_region  = "eu-north-1"
environment = "dev"
project     = "claude-terraform"

vpc_cidr             = "10.10.0.0/16"
availability_zones   = ["eu-north-1a", "eu-north-1b", "eu-north-1c"]
private_subnet_cidrs = ["10.10.1.0/24", "10.10.2.0/24", "10.10.3.0/24"]
public_subnet_cidrs  = ["10.10.101.0/24", "10.10.102.0/24", "10.10.103.0/24"]

cluster_version                      = "1.30"
cluster_endpoint_public_access       = true
cluster_endpoint_public_access_cidrs = ["0.0.0.0/0"]

proxy_instance_type = "t4g.nano"

db_instance_class        = "db.t4g.medium"
db_backup_retention_days = 7
db_deletion_protection   = false
db_skip_final_snapshot   = true

node_groups = {
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
