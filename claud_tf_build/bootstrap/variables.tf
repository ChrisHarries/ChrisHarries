variable "aws_region" {
  description = "AWS region to create the state bucket and lock table in"
  type        = string
  default     = "eu-north-1"
}

variable "project" {
  description = "Project name — used to build unique bucket and table names"
  type        = string
}

variable "environment" {
  description = "Deployment environment (e.g. dev, staging, prod)"
  type        = string
}
