output "organization_id" {
  description = "ID of the AWS Organization"
  value       = aws_organizations_organization.this.id
}

output "organization_arn" {
  description = "ARN of the AWS Organization"
  value       = aws_organizations_organization.this.arn
}

output "root_id" {
  description = "ID of the Organization root"
  value       = aws_organizations_organization.this.roots[0].id
}

output "ou_workloads_id" {
  description = "ID of the Workloads OU"
  value       = aws_organizations_organizational_unit.workloads.id
}

output "ou_production_id" {
  description = "ID of the Production OU"
  value       = aws_organizations_organizational_unit.production.id
}

output "ou_development_id" {
  description = "ID of the Development OU"
  value       = aws_organizations_organizational_unit.development.id
}

output "prod_account_id" {
  description = "AWS account ID of the production member account"
  value       = aws_organizations_account.prod.id
}

output "dev_account_id" {
  description = "AWS account ID of the development member account"
  value       = aws_organizations_account.dev.id
}

output "security_account_id" {
  description = "AWS account ID of the security member account"
  value       = aws_organizations_account.security.id
}

output "ou_security_id" {
  description = "ID of the Security OU"
  value       = aws_organizations_organizational_unit.security.id
}

output "cloudtrail_kms_key_arn" {
  description = "ARN of the CloudTrail CMK — pass to security stack for bucket policy reference"
  value       = aws_kms_key.cloudtrail.arn
}
