# Remote state for the production workload account.
# Run bootstrap/ first targeting this account, then replace REPLACE_WITH_ACCOUNT_ID.
# Bucket name format: <project>-prod-tfstate-<account_id>

terraform {
  backend "s3" {
    bucket         = "claude-terraform-prod-tfstate-REPLACE_WITH_ACCOUNT_ID"
    key            = "workloads/terraform.tfstate"
    region         = "eu-north-1"
    dynamodb_table = "claude-terraform-prod-tf-locks"
    encrypt        = true
  }
}
