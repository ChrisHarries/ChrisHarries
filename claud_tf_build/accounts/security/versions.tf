terraform {
  # Pin to a specific minor release. ~> X.Y.0 allows only X.Y.z patch updates.
  # Run `terraform init -upgrade` intentionally when bumping these.
  required_version = "~> 1.9.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.82.0"
    }
    datadog = {
      source  = "DataDog/datadog"
      version = "~> 3.50.0"
    }
  }
}
