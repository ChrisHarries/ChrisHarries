mock_provider "aws" {}

variables {
  name_prefix          = "test-dev"
  vpc_cidr             = "10.0.0.0/16"
  availability_zones   = ["eu-north-1a", "eu-north-1b", "eu-north-1c"]
  private_subnet_cidrs = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnet_cidrs  = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]
  cluster_name         = "test-dev-eks"
}

run "vpc_is_created_with_correct_cidr" {
  command = plan

  assert {
    condition     = aws_vpc.this.cidr_block == var.vpc_cidr
    error_message = "VPC CIDR does not match the input variable"
  }

  assert {
    condition     = aws_vpc.this.enable_dns_support == true
    error_message = "DNS support must be enabled for EKS"
  }

  assert {
    condition     = aws_vpc.this.enable_dns_hostnames == true
    error_message = "DNS hostnames must be enabled for EKS"
  }

  assert {
    condition     = aws_vpc.this.assign_generated_ipv6_cidr_block == true
    error_message = "IPv6 CIDR block must be assigned to the VPC"
  }
}

run "subnet_counts_match_az_count" {
  command = plan

  assert {
    condition     = length(aws_subnet.private) == length(var.availability_zones)
    error_message = "Private subnet count must equal the number of availability zones"
  }

  assert {
    condition     = length(aws_subnet.public) == length(var.availability_zones)
    error_message = "Public subnet count must equal the number of availability zones"
  }
}

run "public_subnets_have_ipv6_and_public_ip" {
  command = plan

  assert {
    condition     = alltrue([for s in aws_subnet.public : s.assign_ipv6_address_on_creation == true])
    error_message = "All public subnets must have IPv6 address assignment enabled"
  }

  assert {
    condition     = alltrue([for s in aws_subnet.public : s.map_public_ip_on_launch == true])
    error_message = "All public subnets must auto-assign public IPv4 on launch"
  }
}

run "private_subnets_have_ipv6" {
  command = plan

  assert {
    condition     = alltrue([for s in aws_subnet.private : s.assign_ipv6_address_on_creation == true])
    error_message = "All private subnets must have IPv6 address assignment enabled"
  }

  assert {
    condition     = alltrue([for s in aws_subnet.private : s.map_public_ip_on_launch == false])
    error_message = "Private subnets must NOT auto-assign public IPs"
  }
}

run "nat_gateway_count_matches_az_count" {
  command = plan

  assert {
    condition     = length(aws_nat_gateway.this) == length(var.availability_zones)
    error_message = "One NAT gateway must be created per availability zone for HA"
  }

  assert {
    condition     = length(aws_eip.nat) == length(var.availability_zones)
    error_message = "One EIP must be created per NAT gateway"
  }
}

run "egress_only_igw_is_created" {
  command = plan

  assert {
    condition     = aws_egress_only_internet_gateway.this.vpc_id != null
    error_message = "An Egress-Only Internet Gateway must be created for IPv6 private subnet egress"
  }
}

run "private_route_tables_have_ipv6_route_to_eigw" {
  command = plan

  assert {
    condition     = length(aws_route_table.private) == length(var.availability_zones)
    error_message = "One private route table must exist per AZ"
  }
}

run "public_subnets_have_eks_elb_tag" {
  command = plan

  assert {
    condition     = alltrue([
      for s in aws_subnet.public :
      lookup(s.tags, "kubernetes.io/role/elb", "") == "1"
    ])
    error_message = "Public subnets must have the kubernetes.io/role/elb=1 tag for the AWS Load Balancer Controller"
  }
}

run "private_subnets_have_eks_internal_elb_tag" {
  command = plan

  assert {
    condition     = alltrue([
      for s in aws_subnet.private :
      lookup(s.tags, "kubernetes.io/role/internal-elb", "") == "1"
    ])
    error_message = "Private subnets must have the kubernetes.io/role/internal-elb=1 tag"
  }
}
