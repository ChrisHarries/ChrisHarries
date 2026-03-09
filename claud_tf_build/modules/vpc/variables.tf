variable "name_prefix" {
  description = "Prefix for resource names"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
}

variable "availability_zones" {
  description = "List of availability zones"
  type        = list(string)
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets"
  type        = list(string)
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets"
  type        = list(string)
}

variable "cluster_name" {
  description = "EKS cluster name, used for subnet tags required by the AWS load balancer controller"
  type        = string
}

variable "squid_port" {
  description = "Port the Squid proxy listens on. A NACL DENY rule blocks this port on public-subnet internet-facing ingress so the proxy cannot be reached from outside the VPC."
  type        = number
  default     = 3128
}
