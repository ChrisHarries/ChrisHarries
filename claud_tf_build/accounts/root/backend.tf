# Remote state for the management/root account.
# Run bootstrap/ first targeting this account, then replace REPLACE_WITH_ACCOUNT_ID.
# Bucket name format: <project>-root-tfstate-<account_id>

terraform {
  backend "s3" {
    bucket         = "claude-terraform-root-tfstate-REPLACE_WITH_ACCOUNT_ID"
    key            = "organizations/terraform.tfstate"
    region         = "eu-north-1"
    dynamodb_table = "claude-terraform-root-tf-locks"
    encrypt        = true
  }
}
