output "node_group_arns" {
  description = "ARNs of the managed node groups"
  value       = { for k, v in aws_eks_node_group.this : k => v.arn }
}

output "node_group_statuses" {
  description = "Statuses of the managed node groups"
  value       = { for k, v in aws_eks_node_group.this : k => v.status }
}
