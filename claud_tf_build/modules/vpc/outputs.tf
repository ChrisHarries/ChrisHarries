output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.this.id
}

output "vpc_ipv6_cidr_block" {
  description = "AWS-assigned IPv6 /56 CIDR block of the VPC"
  value       = aws_vpc.this.ipv6_cidr_block
}

output "private_subnet_ids" {
  description = "IDs of the private subnets"
  value       = aws_subnet.private[*].id
}

output "private_subnet_ipv6_cidrs" {
  description = "IPv6 /64 CIDR blocks of the private subnets"
  value       = aws_subnet.private[*].ipv6_cidr_block
}

output "public_subnet_ids" {
  description = "IDs of the public subnets"
  value       = aws_subnet.public[*].id
}

output "public_subnet_ipv6_cidrs" {
  description = "IPv6 /64 CIDR blocks of the public subnets"
  value       = aws_subnet.public[*].ipv6_cidr_block
}

output "nat_gateway_ids" {
  description = "IDs of the NAT gateways"
  value       = aws_nat_gateway.this[*].id
}

output "egress_only_igw_id" {
  description = "ID of the Egress-Only Internet Gateway (IPv6 outbound for private subnets)"
  value       = aws_egress_only_internet_gateway.this.id
}

output "vpc_endpoint_s3_id" {
  description = "ID of the S3 Gateway VPC endpoint"
  value       = aws_vpc_endpoint.s3.id
}

output "vpc_endpoint_ecr_api_id" {
  description = "ID of the ECR API Interface VPC endpoint"
  value       = aws_vpc_endpoint.ecr_api.id
}

output "vpc_endpoint_ecr_dkr_id" {
  description = "ID of the ECR DKR Interface VPC endpoint"
  value       = aws_vpc_endpoint.ecr_dkr.id
}

output "vpc_endpoint_secretsmanager_id" {
  description = "ID of the Secrets Manager Interface VPC endpoint"
  value       = aws_vpc_endpoint.secretsmanager.id
}

output "vpc_endpoint_sts_id" {
  description = "ID of the STS Interface VPC endpoint"
  value       = aws_vpc_endpoint.sts.id
}

output "vpc_endpoints_security_group_id" {
  description = "Security group ID attached to all Interface VPC endpoints"
  value       = aws_security_group.vpc_endpoints.id
}
