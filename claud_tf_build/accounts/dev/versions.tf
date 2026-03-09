terraform {
  # Pin to a specific minor release. ~> X.Y.0 allows only X.Y.z patch updates.
  # Run `terraform init -upgrade` intentionally when bumping these.
  required_version = "~> 1.9.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.82.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.35.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0.6"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.17.0"
    }
    datadog = {
      source  = "DataDog/datadog"
      version = "~> 3.50.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.7.0"
    }
  }
}
