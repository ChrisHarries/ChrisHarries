output "vpc_id" {
  description = "ID of the VPC"
  value       = module.vpc.vpc_id
}

output "private_subnet_ids" {
  description = "IDs of the private subnets"
  value       = module.vpc.private_subnet_ids
}

output "public_subnet_ids" {
  description = "IDs of the public subnets"
  value       = module.vpc.public_subnet_ids
}

output "cluster_name" {
  description = "Name of the EKS cluster"
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "Endpoint URL of the EKS cluster API server"
  value       = module.eks.cluster_endpoint
}

output "cluster_certificate_authority_data" {
  description = "Base64-encoded certificate authority data for the cluster"
  value       = module.eks.cluster_certificate_authority_data
  sensitive   = true
}

output "proxy_url" {
  description = "HTTP proxy URL — set as HTTP_PROXY and HTTPS_PROXY on nodes/pods"
  value       = module.proxy.proxy_url
}

output "proxy_public_ip" {
  description = "Public EIP of the proxy — allowlist this on external services"
  value       = module.proxy.proxy_public_ip
}

output "db_cluster_endpoint" {
  description = "Aurora writer endpoint"
  value       = module.database.cluster_endpoint
}

output "db_cluster_reader_endpoint" {
  description = "Aurora read-only endpoint"
  value       = module.database.cluster_reader_endpoint
}

output "db_secret_arn" {
  description = "Secrets Manager ARN containing Aurora credentials"
  value       = module.database.secret_arn
}

output "datadog_integration_role_arn" {
  description = "IAM role ARN that Datadog assumes for the AWS integration"
  value       = module.datadog.datadog_integration_role_arn
}

output "kubeconfig_command" {
  description = "AWS CLI command to update local kubeconfig"
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${module.eks.cluster_name}"
}

output "dd_api_key_secret_arn" {
  description = "Secrets Manager ARN for the Datadog API key (rotated automatically)"
  value       = module.datadog.api_key_secret_arn
}

output "dd_app_key_secret_arn" {
  description = "Secrets Manager ARN for the Datadog application key (static)"
  value       = module.datadog.app_key_secret_arn
}

output "dd_rotation_lambda_arn" {
  description = "ARN of the Lambda function that rotates the Datadog API key"
  value       = module.secret_rotation.lambda_arn
}
