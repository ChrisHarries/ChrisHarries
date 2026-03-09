mock_provider "aws" {}
mock_provider "datadog" {}

variables {
  name_prefix                  = "test-dev"
  datadog_external_id          = "D474D06"
  eks_cluster_name             = "test-dev-eks"
  rds_cluster_id               = "test-dev-aurora-pg"
  cloudwatch_log_groups        = []
  monitor_notification_targets = []
  node_cpu_critical            = 90
  node_cpu_warning             = 80
  node_memory_critical         = 90
  node_memory_warning          = 80
  pod_restart_critical         = 10
  pod_restart_warning          = 5
  aurora_cpu_critical          = 85
  aurora_cpu_warning           = 70
  aurora_connections_critical  = 80
}

run "iam_role_trusts_datadog_aws_account" {
  command = plan

  assert {
    condition     = can(jsondecode(aws_iam_role.datadog_integration.assume_role_policy))
    error_message = "Datadog IAM role assume policy must be valid JSON"
  }

  assert {
    condition     = aws_iam_role.datadog_integration.name == "test-dev-datadog-integration"
    error_message = "Datadog IAM role name must follow naming convention"
  }
}

run "iam_policy_is_attached_to_role" {
  command = plan

  assert {
    condition     = aws_iam_role_policy_attachment.datadog_permissions.role == aws_iam_role.datadog_integration.name
    error_message = "Datadog permissions policy must be attached to the integration role"
  }
}

run "all_monitors_are_created" {
  command = plan

  assert {
    condition     = aws_security_group_rule.cluster_egress_all != null || datadog_monitor.eks_node_cpu.name != null
    error_message = "EKS node CPU monitor must be created"
  }

  assert {
    condition     = datadog_monitor.eks_node_memory.name == "[test-dev] EKS Node Memory High"
    error_message = "EKS node memory monitor name must include the name_prefix"
  }

  assert {
    condition     = datadog_monitor.pod_restarts.name == "[test-dev] Pod Restart Loop Detected"
    error_message = "Pod restart monitor must be created with correct name"
  }

  assert {
    condition     = datadog_monitor.aurora_cpu.name == "[test-dev] Aurora CPU High"
    error_message = "Aurora CPU monitor must be created"
  }

  assert {
    condition     = datadog_monitor.aurora_connections.name == "[test-dev] Aurora Connection Count High"
    error_message = "Aurora connections monitor must be created"
  }

  assert {
    condition     = datadog_monitor.aurora_replica_lag.name == "[test-dev] Aurora Replica Lag High"
    error_message = "Aurora replica lag monitor must be created"
  }
}

run "monitor_thresholds_match_variables" {
  command = plan

  assert {
    condition     = datadog_monitor.eks_node_cpu.monitor_thresholds[0].critical == var.node_cpu_critical
    error_message = "EKS node CPU critical threshold must match the input variable"
  }

  assert {
    condition     = datadog_monitor.eks_node_cpu.monitor_thresholds[0].warning == var.node_cpu_warning
    error_message = "EKS node CPU warning threshold must match the input variable"
  }

  assert {
    condition     = datadog_monitor.aurora_cpu.monitor_thresholds[0].critical == var.aurora_cpu_critical
    error_message = "Aurora CPU critical threshold must match the input variable"
  }
}

run "log_pipeline_targets_correct_cluster" {
  command = plan

  assert {
    condition     = datadog_logs_pipeline.kubernetes.name == "test-dev Kubernetes"
    error_message = "Log pipeline name must include the name_prefix"
  }
}
