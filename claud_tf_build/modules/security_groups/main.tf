# ------------------------------------------------------------------
# Cluster Security Group (control plane)
# ------------------------------------------------------------------

resource "aws_security_group" "cluster" {
  name        = "${var.name_prefix}-eks-cluster-sg"
  description = "Security group for the EKS cluster control plane"
  vpc_id      = var.vpc_id

  tags = {
    Name = "${var.name_prefix}-eks-cluster-sg"
  }
}

# Allow nodes to communicate with the cluster API
resource "aws_security_group_rule" "cluster_ingress_from_nodes" {
  description              = "Allow worker nodes to communicate with the cluster API"
  type                     = "ingress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  security_group_id        = aws_security_group.cluster.id
  source_security_group_id = aws_security_group.node.id
}

# Cluster control plane egress is restricted to the VPC. Internet-bound traffic
# (e.g. AWS API calls) routes through VPC endpoints or the Squid proxy, both of
# which are within the VPC CIDR, so 0.0.0.0/0 is not required here.
resource "aws_security_group_rule" "cluster_egress_to_vpc_ipv4" {
  description       = "Allow cluster control plane outbound within VPC (IPv4)"
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = [var.vpc_cidr]
  security_group_id = aws_security_group.cluster.id
}

resource "aws_security_group_rule" "cluster_egress_to_vpc_ipv6" {
  description       = "Allow cluster control plane outbound within VPC (IPv6)"
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  ipv6_cidr_blocks  = [var.vpc_ipv6_cidr_block]
  security_group_id = aws_security_group.cluster.id
}

# ------------------------------------------------------------------
# Node Security Group (worker nodes)
# ------------------------------------------------------------------

resource "aws_security_group" "node" {
  name        = "${var.name_prefix}-eks-node-sg"
  description = "Security group for EKS worker nodes"
  vpc_id      = var.vpc_id

  tags = {
    Name                                        = "${var.name_prefix}-eks-node-sg"
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
  }
}

# Nodes communicate with each other
resource "aws_security_group_rule" "node_ingress_self" {
  description              = "Allow nodes to communicate with each other"
  type                     = "ingress"
  from_port                = 0
  to_port                  = 65535
  protocol                 = "-1"
  security_group_id        = aws_security_group.node.id
  source_security_group_id = aws_security_group.node.id
}

# Cluster API communicates back to nodes (kubelet, etc.)
resource "aws_security_group_rule" "node_ingress_from_cluster" {
  description              = "Allow cluster control plane to communicate with worker nodes"
  type                     = "ingress"
  from_port                = 1025
  to_port                  = 65535
  protocol                 = "tcp"
  security_group_id        = aws_security_group.node.id
  source_security_group_id = aws_security_group.cluster.id
}

# Cluster API to nodes on 443 (metrics server, webhooks, etc.)
resource "aws_security_group_rule" "node_ingress_from_cluster_443" {
  description              = "Allow cluster control plane to reach nodes on 443 (webhooks)"
  type                     = "ingress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  security_group_id        = aws_security_group.node.id
  source_security_group_id = aws_security_group.cluster.id
}

# Node egress is restricted to the VPC. Internet-bound traffic from pods/nodes
# routes through the Squid proxy (which sits in the public subnet, within the
# VPC CIDR). AWS service traffic routes through VPC endpoints. Neither path
# requires a direct 0.0.0.0/0 egress rule on the node security group.
resource "aws_security_group_rule" "node_egress_to_vpc_ipv4" {
  description       = "Allow worker node outbound within VPC (IPv4) — internet via Squid proxy"
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = [var.vpc_cidr]
  security_group_id = aws_security_group.node.id
}

resource "aws_security_group_rule" "node_egress_to_vpc_ipv6" {
  description       = "Allow worker node outbound within VPC (IPv6)"
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  ipv6_cidr_blocks  = [var.vpc_ipv6_cidr_block]
  security_group_id = aws_security_group.node.id
}
