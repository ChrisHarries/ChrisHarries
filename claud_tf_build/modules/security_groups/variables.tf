variable "name_prefix" {
  description = "Prefix for resource names"
  type        = string
}

variable "vpc_id" {
  description = "ID of the VPC"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block of the VPC"
  type        = string
}

variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "vpc_ipv6_cidr_block" {
  description = "AWS-assigned IPv6 /56 CIDR block of the VPC. Egress is restricted to this range so internet-bound IPv6 is also forced through the proxy."
  type        = string
}
