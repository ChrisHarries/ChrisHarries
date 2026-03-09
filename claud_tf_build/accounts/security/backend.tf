# Remote state for the security account.
# Run bootstrap/ first targeting the security account, then replace REPLACE_WITH_ACCOUNT_ID.
# Bucket name format: <project>-security-tfstate-<account_id>

terraform {
  backend "s3" {
    bucket         = "claude-terraform-security-tfstate-REPLACE_WITH_ACCOUNT_ID"
    key            = "security/terraform.tfstate"
    region         = "eu-north-1"
    dynamodb_table = "claude-terraform-security-tf-locks"
    encrypt        = true
  }
}
