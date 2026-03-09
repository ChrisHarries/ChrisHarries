output "lambda_arn" {
  description = "ARN of the Datadog key rotation Lambda function"
  value       = aws_lambda_function.dd_key_rotation.arn
}

output "lambda_function_name" {
  description = "Name of the Datadog key rotation Lambda function"
  value       = aws_lambda_function.dd_key_rotation.function_name
}

output "lambda_security_group_id" {
  description = "Security group ID attached to the rotation Lambda"
  value       = aws_security_group.rotation_lambda.id
}

output "lambda_role_arn" {
  description = "IAM role ARN used by the rotation Lambda"
  value       = aws_iam_role.rotation_lambda.arn
}
