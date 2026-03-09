output "cluster_endpoint" {
  description = "Writer endpoint for the Aurora cluster"
  value       = aws_rds_cluster.this.endpoint
}

output "cluster_reader_endpoint" {
  description = "Read-only endpoint for the Aurora cluster"
  value       = aws_rds_cluster.this.reader_endpoint
}

output "cluster_port" {
  description = "Port the Aurora cluster listens on"
  value       = aws_rds_cluster.this.port
}

output "cluster_id" {
  description = "ID of the Aurora cluster"
  value       = aws_rds_cluster.this.id
}

output "database_name" {
  description = "Name of the initial database"
  value       = aws_rds_cluster.this.database_name
}

output "master_username" {
  description = "Master username for the Aurora cluster"
  value       = aws_rds_cluster.this.master_username
  sensitive   = true
}

output "secret_arn" {
  description = "ARN of the AWS-managed Secrets Manager secret containing Aurora credentials (rotated automatically by RDS)"
  value       = aws_rds_cluster.this.master_user_secret[0].secret_arn
}

output "security_group_id" {
  description = "Security group ID for the Aurora cluster"
  value       = aws_security_group.db.id
}

output "rotation_lambda_security_group_id" {
  description = "Security group ID to assign to the rotation Lambda so it can reach the DB"
  value       = aws_security_group.rotation_lambda.id
}
