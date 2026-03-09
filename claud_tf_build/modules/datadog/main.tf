data "aws_caller_identity" "current" {}

# ------------------------------------------------------------------
# Secrets Manager — store Datadog keys so rotation Lambda can access them
# The secret payload is a JSON object with "api_key" and "app_key" fields.
# The rotation module handles the api_key lifecycle; app_key is static.
# ------------------------------------------------------------------

resource "aws_secretsmanager_secret" "dd_api_key" {
  name        = "${var.name_prefix}-datadog-api-key"
  description = "Datadog API key for the ${var.name_prefix} stack (rotated automatically)"

  # CMK encryption: every decrypt call is audited via CloudTrail.
  kms_key_id = var.kms_key_id

  # 30-day recovery window — prevents immediate permanent deletion.
  recovery_window_in_days = 30

  tags = { Name = "${var.name_prefix}-datadog-api-key" }
}

resource "aws_secretsmanager_secret_version" "dd_api_key" {
  secret_id = aws_secretsmanager_secret.dd_api_key.id
  secret_string = jsonencode({
    api_key    = var.datadog_api_key
    DD_API_KEY = var.datadog_api_key
    app_key    = var.datadog_app_key
    DD_APP_KEY = var.datadog_app_key
  })

  # After the first apply the rotation Lambda owns the secret value.
  # Ignore drift so Terraform does not overwrite the rotated key.
  lifecycle {
    ignore_changes = [secret_string]
  }
}

resource "aws_secretsmanager_secret" "dd_app_key" {
  name        = "${var.name_prefix}-datadog-app-key"
  description = "Datadog application key for the ${var.name_prefix} stack (static — used by rotation Lambda)"

  kms_key_id              = var.kms_key_id
  recovery_window_in_days = 30

  tags = { Name = "${var.name_prefix}-datadog-app-key" }
}

resource "aws_secretsmanager_secret_version" "dd_app_key" {
  secret_id     = aws_secretsmanager_secret.dd_app_key.id
  secret_string = jsonencode({ app_key = var.datadog_app_key })

  lifecycle {
    ignore_changes = [secret_string]
  }
}

# ------------------------------------------------------------------
# IAM Role — Datadog AWS Integration (cross-account read access)
# Datadog's AWS account (464622532012) assumes this role.
# ------------------------------------------------------------------

data "aws_iam_policy_document" "datadog_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::464622532012:root"] # Datadog's AWS account
    }

    condition {
      test     = "StringEquals"
      variable = "sts:ExternalId"
      values   = [var.datadog_external_id]
    }
  }
}

resource "aws_iam_role" "datadog_integration" {
  name               = "${var.name_prefix}-datadog-integration"
  assume_role_policy = data.aws_iam_policy_document.datadog_assume_role.json

  tags = { Name = "${var.name_prefix}-datadog-integration" }
}

# Datadog-recommended read permissions across the enabled services
data "aws_iam_policy_document" "datadog_permissions" {
  statement {
    sid    = "DatadogCore"
    effect = "Allow"
    actions = [
      "cloudwatch:Get*",
      "cloudwatch:List*",
      "cloudwatch:Describe*",
      "ec2:Describe*",
      "ec2:Get*",
      "autoscaling:Describe*",
      "elasticloadbalancing:Describe*",
      "logs:Get*",
      "logs:List*",
      "logs:Describe*",
      "logs:FilterLogEvents",
      "logs:StartQuery",
      "logs:StopQuery",
      "logs:GetQueryResults",
      "tag:GetResources",
      "tag:GetTagKeys",
      "tag:GetTagValues",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "DatadogEKS"
    effect = "Allow"
    actions = [
      "eks:List*",
      "eks:Describe*",
      "eks:AccessKubernetesApi",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "DatadogRDS"
    effect = "Allow"
    actions = [
      "rds:Describe*",
      "rds:List*",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "DatadogSecrets"
    effect = "Allow"
    actions = [
      "secretsmanager:ListSecrets",
      "secretsmanager:DescribeSecret",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "datadog_permissions" {
  name   = "${var.name_prefix}-datadog-permissions"
  policy = data.aws_iam_policy_document.datadog_permissions.json

  tags = { Name = "${var.name_prefix}-datadog-permissions" }
}

resource "aws_iam_role_policy_attachment" "datadog_permissions" {
  role       = aws_iam_role.datadog_integration.name
  policy_arn = aws_iam_policy.datadog_permissions.arn
}

# ------------------------------------------------------------------
# Datadog AWS Integration
# ------------------------------------------------------------------

resource "datadog_integration_aws" "this" {
  account_id                       = data.aws_caller_identity.current.account_id
  role_name                        = aws_iam_role.datadog_integration.name
  filter_tags                      = ["Project:${var.name_prefix}"]
  host_tags                        = ["env:${split("-", var.name_prefix)[1]}", "project:${split("-", var.name_prefix)[0]}"]
  account_specific_namespace_rules = {}

  depends_on = [aws_iam_role_policy_attachment.datadog_permissions]
}

# ------------------------------------------------------------------
# Log Collection — CloudWatch log groups → Datadog
# ------------------------------------------------------------------

resource "datadog_integration_aws_log_collection" "this" {
  account_id = data.aws_caller_identity.current.account_id

  services = [
    "eks",
    "rds",
  ]

  depends_on = [datadog_integration_aws.this]
}

# ------------------------------------------------------------------
# Log Pipeline — parse and enrich Kubernetes logs
# ------------------------------------------------------------------

resource "datadog_logs_pipeline" "kubernetes" {
  name       = "${var.name_prefix} Kubernetes"
  is_enabled = true
  filter {
    query = "source:kubernetes cluster_name:${var.eks_cluster_name}"
  }

  processor {
    json_parser {
      name       = "Parse log message as JSON"
      is_enabled = true
      source     = "message"
      target     = "msg"
    }
  }

  processor {
    grok_parser {
      name       = "Extract Kubernetes metadata"
      is_enabled = true
      source     = "message"
      grok {
        support_rules = ""
        match_rules   = "kube_meta %{data:kubernetes}"
      }
    }
  }
}

# ------------------------------------------------------------------
# Datadog Monitors
# ------------------------------------------------------------------

locals {
  notify = length(var.monitor_notification_targets) > 0 ? "\n${join(" ", var.monitor_notification_targets)}" : ""
}

# --- EKS Node CPU ---
resource "datadog_monitor" "eks_node_cpu" {
  name    = "[${var.name_prefix}] EKS Node CPU High"
  type    = "metric alert"
  message = "EKS node CPU is critically high on cluster ${var.eks_cluster_name}.${local.notify}"

  query = "avg(last_10m):avg:kubernetes.cpu.usage.total{cluster_name:${var.eks_cluster_name}} by {host} / avg:kubernetes.cpu.limits{cluster_name:${var.eks_cluster_name}} by {host} * 100 > ${var.node_cpu_critical}"

  monitor_thresholds {
    critical = var.node_cpu_critical
    warning  = var.node_cpu_warning
  }

  notify_no_data    = false
  renotify_interval = 60

  tags = ["env:${split("-", var.name_prefix)[1]}", "cluster:${var.eks_cluster_name}", "managed-by:terraform"]
}

# --- EKS Node Memory ---
resource "datadog_monitor" "eks_node_memory" {
  name    = "[${var.name_prefix}] EKS Node Memory High"
  type    = "metric alert"
  message = "EKS node memory usage is critically high on cluster ${var.eks_cluster_name}.${local.notify}"

  query = "avg(last_10m):avg:kubernetes.memory.usage{cluster_name:${var.eks_cluster_name}} by {host} / avg:kubernetes.memory.limits{cluster_name:${var.eks_cluster_name}} by {host} * 100 > ${var.node_memory_critical}"

  monitor_thresholds {
    critical = var.node_memory_critical
    warning  = var.node_memory_warning
  }

  notify_no_data    = false
  renotify_interval = 60

  tags = ["env:${split("-", var.name_prefix)[1]}", "cluster:${var.eks_cluster_name}", "managed-by:terraform"]
}

# --- Pod Restart Loop ---
resource "datadog_monitor" "pod_restarts" {
  name    = "[${var.name_prefix}] Pod Restart Loop Detected"
  type    = "metric alert"
  message = "A pod in cluster ${var.eks_cluster_name} is restarting repeatedly — possible crash loop.${local.notify}"

  query = "change(sum(last_10m),last_10m):sum:kubernetes.containers.restarts{cluster_name:${var.eks_cluster_name}} by {pod_name} > ${var.pod_restart_critical}"

  monitor_thresholds {
    critical = var.pod_restart_critical
    warning  = var.pod_restart_warning
  }

  notify_no_data    = false
  renotify_interval = 30

  tags = ["env:${split("-", var.name_prefix)[1]}", "cluster:${var.eks_cluster_name}", "managed-by:terraform"]
}

# --- EKS Node Not Ready ---
resource "datadog_monitor" "eks_node_not_ready" {
  name    = "[${var.name_prefix}] EKS Node Not Ready"
  type    = "metric alert"
  message = "One or more EKS nodes in ${var.eks_cluster_name} are in NotReady state.${local.notify}"

  query = "max(last_5m):sum:kubernetes_state.node.status{cluster_name:${var.eks_cluster_name},status:ready} < 1"

  monitor_thresholds {
    critical = 1
  }

  notify_no_data    = true
  no_data_timeframe = 10
  renotify_interval = 15

  tags = ["env:${split("-", var.name_prefix)[1]}", "cluster:${var.eks_cluster_name}", "managed-by:terraform"]
}

# --- Aurora CPU ---
resource "datadog_monitor" "aurora_cpu" {
  name    = "[${var.name_prefix}] Aurora CPU High"
  type    = "metric alert"
  message = "Aurora cluster ${var.rds_cluster_id} CPU is critically high.${local.notify}"

  query = "avg(last_10m):avg:aws.rds.cpuutilization{dbclusteridentifier:${var.rds_cluster_id}} > ${var.aurora_cpu_critical}"

  monitor_thresholds {
    critical = var.aurora_cpu_critical
    warning  = var.aurora_cpu_warning
  }

  notify_no_data    = false
  renotify_interval = 60

  tags = ["env:${split("-", var.name_prefix)[1]}", "db:${var.rds_cluster_id}", "managed-by:terraform"]
}

# --- Aurora Connections ---
resource "datadog_monitor" "aurora_connections" {
  name    = "[${var.name_prefix}] Aurora Connection Count High"
  type    = "metric alert"
  message = "Aurora cluster ${var.rds_cluster_id} has a high number of active connections.${local.notify}"

  query = "avg(last_5m):avg:aws.rds.database_connections{dbclusteridentifier:${var.rds_cluster_id}} > ${var.aurora_connections_critical}"

  monitor_thresholds {
    critical = var.aurora_connections_critical
    warning  = var.aurora_connections_critical * 0.8
  }

  notify_no_data    = false
  renotify_interval = 60

  tags = ["env:${split("-", var.name_prefix)[1]}", "db:${var.rds_cluster_id}", "managed-by:terraform"]
}

# --- Aurora Replica Lag ---
resource "datadog_monitor" "aurora_replica_lag" {
  name    = "[${var.name_prefix}] Aurora Replica Lag High"
  type    = "metric alert"
  message = "Aurora replica lag on ${var.rds_cluster_id} is high — reads may be stale.${local.notify}"

  query = "avg(last_5m):avg:aws.rds.aurora_replica_lag{dbclusteridentifier:${var.rds_cluster_id}} > 5000"

  monitor_thresholds {
    critical = 5000
    warning  = 2000
  }

  notify_no_data    = false
  renotify_interval = 30

  tags = ["env:${split("-", var.name_prefix)[1]}", "db:${var.rds_cluster_id}", "managed-by:terraform"]
}
