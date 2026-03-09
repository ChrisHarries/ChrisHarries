mock_provider "aws" {}

variables {
  name_prefix  = "test-dev"
  vpc_id       = "vpc-12345678"
  vpc_cidr     = "10.0.0.0/16"
  cluster_name = "test-dev-eks"
}

run "cluster_sg_is_created" {
  command = plan

  assert {
    condition     = aws_security_group.cluster.name == "test-dev-eks-cluster-sg"
    error_message = "Cluster security group name does not match naming convention"
  }

  assert {
    condition     = aws_security_group.cluster.vpc_id == var.vpc_id
    error_message = "Cluster security group must be in the correct VPC"
  }
}

run "node_sg_is_created" {
  command = plan

  assert {
    condition     = aws_security_group.node.name == "test-dev-eks-node-sg"
    error_message = "Node security group name does not match naming convention"
  }

  assert {
    condition     = aws_security_group.node.vpc_id == var.vpc_id
    error_message = "Node security group must be in the correct VPC"
  }
}

run "node_sg_has_eks_owned_tag" {
  command = plan

  assert {
    condition     = lookup(aws_security_group.node.tags, "kubernetes.io/cluster/${var.cluster_name}", "") == "owned"
    error_message = "Node security group must have the kubernetes.io/cluster/<name>=owned tag"
  }
}

run "cluster_egress_has_ipv6" {
  command = plan

  assert {
    condition     = contains(aws_security_group_rule.cluster_egress_all.ipv6_cidr_blocks, "::/0")
    error_message = "Cluster egress rule must include ::/0 for IPv6 outbound"
  }
}

run "node_egress_has_ipv4_and_ipv6" {
  command = plan

  assert {
    condition     = contains(aws_security_group_rule.node_egress_all.cidr_blocks, "0.0.0.0/0")
    error_message = "Node egress rule must include 0.0.0.0/0 for IPv4 outbound"
  }

  assert {
    condition     = contains(aws_security_group_rule.node_egress_all.ipv6_cidr_blocks, "::/0")
    error_message = "Node egress rule must include ::/0 for IPv6 outbound"
  }
}

run "cluster_ingress_from_nodes_on_443" {
  command = plan

  assert {
    condition     = aws_security_group_rule.cluster_ingress_from_nodes.from_port == 443
    error_message = "Cluster must accept ingress from nodes on port 443"
  }

  assert {
    condition     = aws_security_group_rule.cluster_ingress_from_nodes.to_port == 443
    error_message = "Cluster ingress from nodes must be restricted to port 443"
  }
}
