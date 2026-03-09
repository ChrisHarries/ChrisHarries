mock_provider "aws" {}
mock_provider "tls" {}

variables {
  name_prefix                          = "test-dev"
  cluster_version                      = "1.30"
  vpc_id                               = "vpc-12345678"
  subnet_ids                           = ["subnet-aaa", "subnet-bbb", "subnet-ccc"]
  cluster_role_arn                     = "arn:aws:iam::123456789012:role/test-dev-eks-cluster-role"
  cluster_security_group_id            = "sg-12345678"
  cluster_endpoint_public_access       = true
  cluster_endpoint_public_access_cidrs = ["0.0.0.0/0"]
  ip_family                            = "ipv6"
}

run "cluster_has_correct_name_and_version" {
  command = plan

  assert {
    condition     = aws_eks_cluster.this.name == "test-dev-eks"
    error_message = "EKS cluster name must follow the <name_prefix>-eks convention"
  }

  assert {
    condition     = aws_eks_cluster.this.version == var.cluster_version
    error_message = "EKS cluster version must match the input variable"
  }
}

run "cluster_has_private_access_enabled" {
  command = plan

  assert {
    condition     = aws_eks_cluster.this.vpc_config[0].endpoint_private_access == true
    error_message = "Private endpoint access must always be enabled"
  }
}

run "cluster_ip_family_is_ipv6" {
  command = plan

  assert {
    condition     = aws_eks_cluster.this.kubernetes_network_config[0].ip_family == "ipv6"
    error_message = "IP family must be set to ipv6"
  }
}

run "cluster_has_all_log_types_enabled" {
  command = plan

  assert {
    condition     = contains(aws_eks_cluster.this.enabled_cluster_log_types, "api")
    error_message = "API server logs must be enabled"
  }

  assert {
    condition     = contains(aws_eks_cluster.this.enabled_cluster_log_types, "audit")
    error_message = "Audit logs must be enabled"
  }

  assert {
    condition     = contains(aws_eks_cluster.this.enabled_cluster_log_types, "authenticator")
    error_message = "Authenticator logs must be enabled"
  }
}

run "cloudwatch_log_group_has_correct_name" {
  command = plan

  assert {
    condition     = aws_cloudwatch_log_group.eks.name == "/aws/eks/test-dev-eks/cluster"
    error_message = "CloudWatch log group must follow the /aws/eks/<cluster-name>/cluster convention"
  }
}

run "core_addons_are_configured" {
  command = plan

  assert {
    condition     = aws_eks_addon.coredns.addon_name == "coredns"
    error_message = "CoreDNS addon must be configured"
  }

  assert {
    condition     = aws_eks_addon.vpc_cni.addon_name == "vpc-cni"
    error_message = "VPC CNI addon must be configured"
  }

  assert {
    condition     = aws_eks_addon.kube_proxy.addon_name == "kube-proxy"
    error_message = "kube-proxy addon must be configured"
  }
}

run "ip_family_validation_rejects_invalid_value" {
  command = plan

  variables {
    ip_family = "invalid"
  }

  expect_failures = [var.ip_family]
}
