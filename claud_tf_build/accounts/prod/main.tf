provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Environment = var.environment
      Project     = var.project
      ManagedBy   = "terraform"
    }
  }
}

provider "datadog" {
  api_key = var.datadog_api_key
  app_key = var.datadog_app_key
  api_url = var.datadog_api_url
}

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
  }
}

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
    }
  }
}

locals {
  name_prefix = "${var.project}-${var.environment}"
}

data "aws_caller_identity" "current" {}

# ------------------------------------------------------------------
# Customer-Managed KMS Keys
# Separate CMKs per resource type give independent audit trails,
# rotation schedules, and revocation capability.
# ------------------------------------------------------------------

resource "aws_kms_key" "rds" {
  description             = "CMK for ${local.name_prefix} Aurora RDS storage and master password"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "EnableRootAdmin"
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root" }
        Action    = "kms:*"
        Resource  = "*"
      },
      {
        Sid    = "AllowRDSService"
        Effect = "Allow"
        Principal = { Service = "rds.amazonaws.com" }
        Action   = ["kms:Decrypt", "kms:GenerateDataKey*", "kms:CreateGrant", "kms:DescribeKey"]
        Resource = "*"
        Condition = {
          StringEquals = { "kms:CallerAccount" = data.aws_caller_identity.current.account_id }
        }
      },
    ]
  })

  lifecycle { prevent_destroy = true }

  tags = { Name = "${local.name_prefix}-rds-key" }
}

resource "aws_kms_alias" "rds" {
  name          = "alias/${local.name_prefix}-rds"
  target_key_id = aws_kms_key.rds.key_id
}

resource "aws_kms_key" "ebs" {
  description             = "CMK for ${local.name_prefix} EBS volumes (proxy and EKS nodes)"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  # EC2 service principal: allows EBS volume encryption and CreateGrant so the
  # AutoScaling service-linked role can launch encrypted EKS node instances.
  # Ensure the SLR exists:
  #   aws iam create-service-linked-role --aws-service-name autoscaling.amazonaws.com
  # CloudWatch Logs principal: encrypts the EKS control plane log group.
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "EnableRootAdmin"
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root" }
        Action    = "kms:*"
        Resource  = "*"
      },
      {
        Sid    = "AllowEC2EBSEncryption"
        Effect = "Allow"
        Principal = { Service = "ec2.amazonaws.com" }
        Action   = ["kms:Decrypt", "kms:GenerateDataKey*", "kms:CreateGrant", "kms:DescribeKey", "kms:ReEncrypt*"]
        Resource = "*"
        Condition = {
          StringEquals = { "kms:CallerAccount" = data.aws_caller_identity.current.account_id }
        }
      },
      {
        Sid    = "AllowCloudWatchLogsEncryption"
        Effect = "Allow"
        Principal = { Service = "logs.${var.aws_region}.amazonaws.com" }
        Action   = ["kms:Encrypt*", "kms:Decrypt*", "kms:ReEncrypt*", "kms:GenerateDataKey*", "kms:Describe*"]
        Resource = "*"
        Condition = {
          ArnLike = {
            "kms:EncryptionContext:aws:logs:arn" = "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:*"
          }
        }
      },
    ]
  })

  lifecycle { prevent_destroy = true }

  tags = { Name = "${local.name_prefix}-ebs-key" }
}

resource "aws_kms_alias" "ebs" {
  name          = "alias/${local.name_prefix}-ebs"
  target_key_id = aws_kms_key.ebs.key_id
}

resource "aws_kms_key" "secrets" {
  description             = "CMK for ${local.name_prefix} Secrets Manager secrets"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "EnableRootAdmin"
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root" }
        Action    = "kms:*"
        Resource  = "*"
      },
      {
        Sid    = "AllowSecretsManagerService"
        Effect = "Allow"
        Principal = { Service = "secretsmanager.amazonaws.com" }
        Action   = ["kms:Decrypt", "kms:GenerateDataKey", "kms:CreateGrant", "kms:DescribeKey"]
        Resource = "*"
        Condition = {
          StringEquals = {
            "kms:ViaService"    = "secretsmanager.${var.aws_region}.amazonaws.com"
            "kms:CallerAccount" = data.aws_caller_identity.current.account_id
          }
        }
      },
    ]
  })

  lifecycle { prevent_destroy = true }

  tags = { Name = "${local.name_prefix}-secrets-key" }
}

resource "aws_kms_alias" "secrets" {
  name          = "alias/${local.name_prefix}-secrets"
  target_key_id = aws_kms_key.secrets.key_id
}

module "vpc" {
  source = "../../modules/vpc"

  name_prefix          = local.name_prefix
  vpc_cidr             = var.vpc_cidr
  availability_zones   = var.availability_zones
  private_subnet_cidrs = var.private_subnet_cidrs
  public_subnet_cidrs  = var.public_subnet_cidrs
  cluster_name         = "${local.name_prefix}-eks"
}

module "iam" {
  source = "../../modules/iam"

  name_prefix = local.name_prefix
}

module "security_groups" {
  source = "../../modules/security_groups"

  name_prefix          = local.name_prefix
  vpc_id               = module.vpc.vpc_id
  vpc_cidr             = var.vpc_cidr
  vpc_ipv6_cidr_block  = module.vpc.vpc_ipv6_cidr_block
  cluster_name         = "${local.name_prefix}-eks"
}

module "eks" {
  source = "../../modules/eks"

  name_prefix                          = local.name_prefix
  cluster_version                      = var.cluster_version
  vpc_id                               = module.vpc.vpc_id
  subnet_ids                           = module.vpc.private_subnet_ids
  cluster_role_arn                     = module.iam.cluster_role_arn
  cluster_security_group_id            = module.security_groups.cluster_security_group_id
  cluster_endpoint_public_access       = var.cluster_endpoint_public_access
  cluster_endpoint_public_access_cidrs = var.cluster_endpoint_public_access_cidrs
  kms_key_id                           = aws_kms_key.ebs.arn
}

module "proxy" {
  source = "../../modules/proxy"

  name_prefix                       = local.name_prefix
  vpc_id                            = module.vpc.vpc_id
  subnet_id                         = module.vpc.public_subnet_ids[0]
  instance_type                     = var.proxy_instance_type
  allowed_source_security_group_ids = [module.security_groups.node_security_group_id]
  squid_port                        = var.proxy_squid_port
  allowed_domains                   = var.proxy_allowed_domains
  kms_key_id                        = aws_kms_key.ebs.arn
}

module "database" {
  source = "../../modules/database"

  name_prefix                      = local.name_prefix
  vpc_id                           = module.vpc.vpc_id
  subnet_ids                       = module.vpc.private_subnet_ids
  allowed_source_security_group_id = module.security_groups.node_security_group_id
  database_name                    = var.db_name
  master_username                  = var.db_master_username
  engine_version                   = var.db_engine_version
  instance_class                   = var.db_instance_class
  backup_retention_days            = var.db_backup_retention_days
  deletion_protection              = var.db_deletion_protection
  skip_final_snapshot              = var.db_skip_final_snapshot
  reserved_instance_enabled        = var.db_reserved_instance_enabled
  reserved_instance_term           = var.db_reserved_instance_term
  reserved_instance_offering_type  = var.db_reserved_instance_offering_type
  kms_key_id                       = aws_kms_key.rds.arn
}

module "node_groups" {
  source = "../../modules/node_groups"

  name_prefix            = local.name_prefix
  cluster_name           = module.eks.cluster_name
  node_role_arn          = module.iam.node_role_arn
  subnet_ids             = module.vpc.private_subnet_ids
  node_security_group_id = module.security_groups.node_security_group_id
  node_groups            = var.node_groups
  kms_key_id             = aws_kms_key.ebs.arn
}

module "datadog" {
  source = "../../modules/datadog"

  name_prefix                  = local.name_prefix
  datadog_external_id          = var.datadog_external_id
  datadog_api_key              = var.datadog_api_key
  datadog_app_key              = var.datadog_app_key
  eks_cluster_name             = module.eks.cluster_name
  rds_cluster_id               = module.database.cluster_id
  monitor_notification_targets = var.datadog_monitor_notification_targets
  kms_key_id                   = aws_kms_key.secrets.arn
  cloudwatch_log_groups = [
    "/aws/eks/${module.eks.cluster_name}/cluster",
    "/aws/rds/cluster/${module.database.cluster_id}/postgresql",
  ]
}

module "secret_rotation" {
  source = "../../modules/secret_rotation"

  name_prefix   = local.name_prefix
  vpc_id        = module.vpc.vpc_id
  subnet_ids    = module.vpc.private_subnet_ids
  secret_arn    = module.datadog.api_key_secret_arn
  rotation_days = var.dd_key_rotation_days
  datadog_site  = var.datadog_site

  depends_on = [module.datadog]
}

# ------------------------------------------------------------------
# Secrets Manager resource policies (#11)
# Created here (not in the datadog module) to avoid a circular
# dependency: the policy references the rotation Lambda role ARN,
# which is only known after secret_rotation is applied.
# ------------------------------------------------------------------

resource "aws_secretsmanager_secret_policy" "dd_api_key" {
  secret_arn = module.datadog.api_key_secret_arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowRotationLambda"
        Effect = "Allow"
        Principal = {
          AWS = module.secret_rotation.lambda_role_arn
        }
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:PutSecretValue",
          "secretsmanager:UpdateSecretVersionStage",
          "secretsmanager:DescribeSecret",
        ]
        Resource = "*"
      },
      {
        Sid       = "DenyAllOthers"
        Effect    = "Deny"
        Principal = { AWS = "*" }
        Action    = "secretsmanager:GetSecretValue"
        Resource  = "*"
        Condition = {
          ArnNotEquals = {
            "aws:PrincipalArn" = module.secret_rotation.lambda_role_arn
          }
        }
      }
    ]
  })

  depends_on = [module.datadog, module.secret_rotation]
}

resource "aws_secretsmanager_secret_policy" "dd_app_key" {
  secret_arn = module.datadog.app_key_secret_arn

  # The app key is only read by the rotation Lambda — deny all other access.
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowRotationLambdaOnly"
        Effect = "Allow"
        Principal = {
          AWS = module.secret_rotation.lambda_role_arn
        }
        Action   = "secretsmanager:GetSecretValue"
        Resource = "*"
      },
      {
        Sid       = "DenyAllOthers"
        Effect    = "Deny"
        Principal = { AWS = "*" }
        Action    = "secretsmanager:GetSecretValue"
        Resource  = "*"
        Condition = {
          ArnNotEquals = {
            "aws:PrincipalArn" = module.secret_rotation.lambda_role_arn
          }
        }
      }
    ]
  })

  depends_on = [module.datadog, module.secret_rotation]
}

# ------------------------------------------------------------------
# Datadog Agent — deployed to EKS via Helm
# ------------------------------------------------------------------

resource "kubernetes_namespace" "datadog" {
  metadata {
    name = "datadog"
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }

  depends_on = [module.node_groups]
}

resource "helm_release" "datadog_agent" {
  name       = "datadog"
  namespace  = kubernetes_namespace.datadog.metadata[0].name
  repository = "https://helm.datadoghq.com"
  chart      = "datadog"
  version    = var.datadog_agent_chart_version

  # Sensitive values — stored in Terraform state; use Vault/ESO in production for keyless injection
  set_sensitive {
    name  = "datadog.apiKey"
    value = var.datadog_api_key
  }

  set_sensitive {
    name  = "datadog.appKey"
    value = var.datadog_app_key
  }

  set {
    name  = "datadog.site"
    value = var.datadog_site
  }

  set {
    name  = "datadog.clusterName"
    value = module.eks.cluster_name
  }

  set {
    name  = "datadog.logs.enabled"
    value = "true"
  }

  set {
    name  = "datadog.logs.containerCollectAll"
    value = "true"
  }

  set {
    name  = "datadog.apm.portEnabled"
    value = "true"
  }

  set {
    name  = "datadog.processAgent.enabled"
    value = "true"
  }

  set {
    name  = "datadog.processAgent.processCollection"
    value = "true"
  }

  set {
    name  = "datadog.kubeStateMetricsEnabled"
    value = "true"
  }

  set {
    name  = "clusterAgent.enabled"
    value = "true"
  }

  set {
    name  = "clusterAgent.replicas"
    value = "2"
  }

  set {
    name  = "clusterAgent.createPodDisruptionBudget"
    value = "true"
  }

  depends_on = [module.node_groups, module.datadog]
}
