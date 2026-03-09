output "cloudtrail_log_bucket_name" {
  description = "Name of the S3 bucket that receives org-wide CloudTrail logs. Set this as cloudtrail_log_bucket_name in accounts/root and re-apply to activate the org trail."
  value       = aws_s3_bucket.cloudtrail_logs.id
}

output "cloudtrail_log_bucket_arn" {
  description = "ARN of the CloudTrail log S3 bucket"
  value       = aws_s3_bucket.cloudtrail_logs.arn
}

output "security_kms_key_arn" {
  description = "ARN of the security account CMK"
  value       = aws_kms_key.security.arn
}

output "guardduty_detector_id" {
  description = "ID of the GuardDuty detector in the security account"
  value       = aws_guardduty_detector.this.id
}

output "config_aggregator_name" {
  description = "Name of the organisation-wide Config aggregator"
  value       = aws_config_configuration_aggregator.org.name
}

output "access_analyzer_arn" {
  description = "ARN of the organisation-wide IAM Access Analyzer"
  value       = aws_accessanalyzer_analyzer.org.arn
}

output "datadog_integration_role_arn" {
  description = "ARN of the Datadog integration IAM role in the security account"
  value       = aws_iam_role.datadog_integration.arn
}
