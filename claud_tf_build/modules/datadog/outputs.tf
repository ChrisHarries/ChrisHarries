output "datadog_integration_role_arn" {
  description = "ARN of the IAM role Datadog assumes for the AWS integration"
  value       = aws_iam_role.datadog_integration.arn
}

output "datadog_integration_external_id" {
  description = "External ID used in the Datadog AWS integration trust policy"
  value       = var.datadog_external_id
}

output "monitor_eks_node_cpu_id" {
  description = "Datadog monitor ID — EKS node CPU"
  value       = datadog_monitor.eks_node_cpu.id
}

output "monitor_eks_node_memory_id" {
  description = "Datadog monitor ID — EKS node memory"
  value       = datadog_monitor.eks_node_memory.id
}

output "monitor_pod_restarts_id" {
  description = "Datadog monitor ID — pod restart loop"
  value       = datadog_monitor.pod_restarts.id
}

output "monitor_aurora_cpu_id" {
  description = "Datadog monitor ID — Aurora CPU"
  value       = datadog_monitor.aurora_cpu.id
}

output "monitor_aurora_connections_id" {
  description = "Datadog monitor ID — Aurora connections"
  value       = datadog_monitor.aurora_connections.id
}

output "api_key_secret_arn" {
  description = "ARN of the Secrets Manager secret containing the Datadog API key (rotated by Lambda)"
  value       = aws_secretsmanager_secret.dd_api_key.arn
}

output "app_key_secret_arn" {
  description = "ARN of the Secrets Manager secret containing the Datadog application key (static)"
  value       = aws_secretsmanager_secret.dd_app_key.arn
}
