# VPC
resource "aws_vpc" "this" {
  cidr_block                       = var.vpc_cidr
  enable_dns_support               = true
  enable_dns_hostnames             = true
  assign_generated_ipv6_cidr_block = true

  tags = {
    Name = "${var.name_prefix}-vpc"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "${var.name_prefix}-igw"
  }
}

# Egress-Only Internet Gateway (IPv6 outbound for private subnets)
resource "aws_egress_only_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "${var.name_prefix}-eigw"
  }
}

# Public Subnets
resource "aws_subnet" "public" {
  count = length(var.public_subnet_cidrs)

  vpc_id                          = aws_vpc.this.id
  cidr_block                      = var.public_subnet_cidrs[count.index]
  ipv6_cidr_block                 = cidrsubnet(aws_vpc.this.ipv6_cidr_block, 8, count.index)
  availability_zone               = var.availability_zones[count.index]
  map_public_ip_on_launch         = true
  assign_ipv6_address_on_creation = true

  tags = {
    Name                                        = "${var.name_prefix}-public-${var.availability_zones[count.index]}"
    "kubernetes.io/role/elb"                    = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }
}

# Private Subnets
resource "aws_subnet" "private" {
  count = length(var.private_subnet_cidrs)

  vpc_id                          = aws_vpc.this.id
  cidr_block                      = var.private_subnet_cidrs[count.index]
  ipv6_cidr_block                 = cidrsubnet(aws_vpc.this.ipv6_cidr_block, 8, count.index + length(var.public_subnet_cidrs))
  availability_zone               = var.availability_zones[count.index]
  assign_ipv6_address_on_creation = true

  tags = {
    Name                                        = "${var.name_prefix}-private-${var.availability_zones[count.index]}"
    "kubernetes.io/role/internal-elb"           = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }
}

# Elastic IPs for NAT Gateways
resource "aws_eip" "nat" {
  count  = length(var.public_subnet_cidrs)
  domain = "vpc"

  tags = {
    Name = "${var.name_prefix}-nat-eip-${count.index}"
  }

  depends_on = [aws_internet_gateway.this]
}

# NAT Gateways (one per AZ for HA)
resource "aws_nat_gateway" "this" {
  count = length(var.public_subnet_cidrs)

  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  tags = {
    Name = "${var.name_prefix}-nat-${var.availability_zones[count.index]}"
  }

  depends_on = [aws_internet_gateway.this]
}

# Public Route Table
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  route {
    ipv6_cidr_block = "::/0"
    gateway_id      = aws_internet_gateway.this.id
  }

  tags = {
    Name = "${var.name_prefix}-public-rt"
  }
}

resource "aws_route_table_association" "public" {
  count = length(aws_subnet.public)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# Private Route Tables (one per AZ)
resource "aws_route_table" "private" {
  count  = length(aws_subnet.private)
  vpc_id = aws_vpc.this.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.this[count.index].id
  }

  route {
    ipv6_cidr_block        = "::/0"
    egress_only_gateway_id = aws_egress_only_internet_gateway.this.id
  }

  tags = {
    Name = "${var.name_prefix}-private-rt-${var.availability_zones[count.index]}"
  }
}

resource "aws_route_table_association" "private" {
  count = length(aws_subnet.private)

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

# ------------------------------------------------------------------
# Network ACLs
# NACLs add a stateless subnet-level layer of defence. Security groups
# remain the primary control — NACLs block direct internet access to
# private subnets while allowing intra-VPC and NAT return traffic.
# ------------------------------------------------------------------

# --- Private subnet NACL ---
# Allows all intra-VPC traffic and NAT return traffic.
# Blocks direct internet ingress on all ports.

resource "aws_network_acl" "private" {
  vpc_id     = aws_vpc.this.id
  subnet_ids = aws_subnet.private[*].id

  tags = { Name = "${var.name_prefix}-private-nacl" }
}

# Inbound 100: allow all from VPC CIDR (IPv4)
resource "aws_network_acl_rule" "private_inbound_vpc_ipv4" {
  network_acl_id = aws_network_acl.private.id
  rule_number    = 100
  egress         = false
  protocol       = "-1"
  rule_action    = "allow"
  cidr_block     = var.vpc_cidr
}

# Inbound 110: allow all from VPC CIDR (IPv6)
resource "aws_network_acl_rule" "private_inbound_vpc_ipv6" {
  network_acl_id  = aws_network_acl.private.id
  rule_number     = 110
  egress          = false
  protocol        = "-1"
  rule_action     = "allow"
  ipv6_cidr_block = aws_vpc.this.ipv6_cidr_block
}

# Inbound 200: allow TCP ephemeral ports from internet (return traffic via NAT gateway)
resource "aws_network_acl_rule" "private_inbound_ephemeral_tcp" {
  network_acl_id = aws_network_acl.private.id
  rule_number    = 200
  egress         = false
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
  from_port      = 1024
  to_port        = 65535
}

# Inbound 210: allow UDP ephemeral ports from internet (DNS/NTP return traffic)
resource "aws_network_acl_rule" "private_inbound_ephemeral_udp" {
  network_acl_id = aws_network_acl.private.id
  rule_number    = 210
  egress         = false
  protocol       = "udp"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
  from_port      = 1024
  to_port        = 65535
}

# Outbound 100/110: allow everything (SGs enforce fine-grained egress)
resource "aws_network_acl_rule" "private_outbound_all_ipv4" {
  network_acl_id = aws_network_acl.private.id
  rule_number    = 100
  egress         = true
  protocol       = "-1"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
}

resource "aws_network_acl_rule" "private_outbound_all_ipv6" {
  network_acl_id  = aws_network_acl.private.id
  rule_number     = 110
  egress          = true
  protocol        = "-1"
  rule_action     = "allow"
  ipv6_cidr_block = "::/0"
}

# --- Public subnet NACL ---
# Allows HTTP/HTTPS from internet, return traffic, and all intra-VPC traffic.

resource "aws_network_acl" "public" {
  vpc_id     = aws_vpc.this.id
  subnet_ids = aws_subnet.public[*].id

  tags = { Name = "${var.name_prefix}-public-nacl" }
}

# Inbound 100/110: allow all from VPC CIDR (covers private → public for NAT)
resource "aws_network_acl_rule" "public_inbound_vpc_ipv4" {
  network_acl_id = aws_network_acl.public.id
  rule_number    = 100
  egress         = false
  protocol       = "-1"
  rule_action    = "allow"
  cidr_block     = var.vpc_cidr
}

resource "aws_network_acl_rule" "public_inbound_vpc_ipv6" {
  network_acl_id  = aws_network_acl.public.id
  rule_number     = 110
  egress          = false
  protocol        = "-1"
  rule_action     = "allow"
  ipv6_cidr_block = aws_vpc.this.ipv6_cidr_block
}

# Inbound 195: Explicitly deny the Squid port from the internet before the
# ephemeral-ports allow-all (rule 200) would otherwise permit it.
# NACLs process rules in ascending order and stop at the first match.
resource "aws_network_acl_rule" "public_inbound_deny_squid" {
  network_acl_id = aws_network_acl.public.id
  rule_number    = 195
  egress         = false
  protocol       = "tcp"
  rule_action    = "deny"
  cidr_block     = "0.0.0.0/0"
  from_port      = var.squid_port
  to_port        = var.squid_port
}

# Inbound 200: TCP ephemeral return traffic from internet
resource "aws_network_acl_rule" "public_inbound_ephemeral_tcp" {
  network_acl_id = aws_network_acl.public.id
  rule_number    = 200
  egress         = false
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
  from_port      = 1024
  to_port        = 65535
}

# Inbound 300/310: HTTPS and HTTP from internet (Squid proxy, NAT gateway)
resource "aws_network_acl_rule" "public_inbound_https" {
  network_acl_id = aws_network_acl.public.id
  rule_number    = 300
  egress         = false
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
  from_port      = 443
  to_port        = 443
}

resource "aws_network_acl_rule" "public_inbound_http" {
  network_acl_id = aws_network_acl.public.id
  rule_number    = 310
  egress         = false
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
  from_port      = 80
  to_port        = 80
}

# Outbound 100/110: allow everything
resource "aws_network_acl_rule" "public_outbound_all_ipv4" {
  network_acl_id = aws_network_acl.public.id
  rule_number    = 100
  egress         = true
  protocol       = "-1"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
}

resource "aws_network_acl_rule" "public_outbound_all_ipv6" {
  network_acl_id  = aws_network_acl.public.id
  rule_number     = 110
  egress          = true
  protocol        = "-1"
  rule_action     = "allow"
  ipv6_cidr_block = "::/0"
}

# ------------------------------------------------------------------
# VPC Endpoints
# Keep AWS API traffic within the AWS network — no NAT gateway charges
# and no internet path for S3, ECR, Secrets Manager, or STS calls.
# ------------------------------------------------------------------

data "aws_region" "current" {}

# Security group shared by all Interface endpoints.
# Allows HTTPS from within the VPC only.
resource "aws_security_group" "vpc_endpoints" {
  name        = "${var.name_prefix}-vpc-endpoints-sg"
  description = "Allow HTTPS from within the VPC to AWS Interface Endpoints"
  vpc_id      = aws_vpc.this.id

  ingress {
    description = "HTTPS from VPC (IPv4)"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  ingress {
    description      = "HTTPS from VPC (IPv6)"
    from_port        = 443
    to_port          = 443
    protocol         = "tcp"
    ipv6_cidr_blocks = [aws_vpc.this.ipv6_cidr_block]
  }

  tags = { Name = "${var.name_prefix}-vpc-endpoints-sg" }
}

# S3 Gateway Endpoint — free; routes S3 traffic (ECR layer pulls, state bucket)
# through the AWS backbone without NAT gateway.
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.${data.aws_region.current.name}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = aws_route_table.private[*].id

  tags = { Name = "${var.name_prefix}-s3-endpoint" }
}

# ECR API Interface Endpoint — used by kubelet to authenticate with ECR.
resource "aws_vpc_endpoint" "ecr_api" {
  vpc_id              = aws_vpc.this.id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.ecr.api"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = { Name = "${var.name_prefix}-ecr-api-endpoint" }
}

# ECR Docker Registry Interface Endpoint — used to pull image manifests; layers
# come from S3 via the gateway endpoint above.
resource "aws_vpc_endpoint" "ecr_dkr" {
  vpc_id              = aws_vpc.this.id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.ecr.dkr"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = { Name = "${var.name_prefix}-ecr-dkr-endpoint" }
}

# Secrets Manager Interface Endpoint — rotation Lambda and app code read secrets
# without leaving the VPC.
resource "aws_vpc_endpoint" "secretsmanager" {
  vpc_id              = aws_vpc.this.id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.secretsmanager"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = { Name = "${var.name_prefix}-secretsmanager-endpoint" }
}

# STS Interface Endpoint — required for IRSA (IAM Roles for Service Accounts)
# so pods can exchange OIDC tokens for AWS credentials without public STS.
resource "aws_vpc_endpoint" "sts" {
  vpc_id              = aws_vpc.this.id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.sts"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = { Name = "${var.name_prefix}-sts-endpoint" }
}
