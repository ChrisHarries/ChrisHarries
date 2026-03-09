output "state_bucket_name" {
  description = "S3 bucket name — copy into backend.tf bucket ="
  value       = aws_s3_bucket.state.bucket
}

output "lock_table_name" {
  description = "DynamoDB table name — copy into backend.tf dynamodb_table ="
  value       = aws_dynamodb_table.locks.name
}

output "backend_tf_snippet" {
  description = "Ready-to-paste backend.tf configuration"
  sensitive   = true
  value       = <<-EOT
    terraform {
      backend "s3" {
        bucket         = "${aws_s3_bucket.state.bucket}"
        key            = "eks/terraform.tfstate"
        region         = "${var.aws_region}"
        dynamodb_table = "${aws_dynamodb_table.locks.name}"
        encrypt        = true
      }
    }
  EOT
}
