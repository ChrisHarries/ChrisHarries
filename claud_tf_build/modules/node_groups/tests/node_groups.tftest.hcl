mock_provider "aws" {}

variables {
  name_prefix            = "test-dev"
  cluster_name           = "test-dev-eks"
  node_role_arn          = "arn:aws:iam::123456789012:role/test-dev-eks-node-role"
  subnet_ids             = ["subnet-aaa", "subnet-bbb", "subnet-ccc"]
  node_security_group_id = "sg-12345678"
  node_groups = {
    general = {
      instance_types = ["t3.medium"]
      capacity_type  = "ON_DEMAND"
      min_size       = 1
      max_size       = 3
      desired_size   = 2
      disk_size_gb   = 50
      labels         = { role = "general" }
      taints         = []
    }
  }
}

run "node_group_is_created_for_each_config" {
  command = plan

  assert {
    condition     = length(aws_eks_node_group.this) == length(var.node_groups)
    error_message = "One node group resource must be created per entry in the node_groups map"
  }
}

run "node_group_has_correct_name" {
  command = plan

  assert {
    condition     = aws_eks_node_group.this["general"].node_group_name == "test-dev-general"
    error_message = "Node group name must follow the <name_prefix>-<key> convention"
  }
}

run "node_group_is_attached_to_correct_cluster" {
  command = plan

  assert {
    condition     = aws_eks_node_group.this["general"].cluster_name == var.cluster_name
    error_message = "Node group must be attached to the correct EKS cluster"
  }
}

run "node_group_scaling_config_matches_input" {
  command = plan

  assert {
    condition     = aws_eks_node_group.this["general"].scaling_config[0].min_size == 1
    error_message = "Node group min_size must match the input variable"
  }

  assert {
    condition     = aws_eks_node_group.this["general"].scaling_config[0].max_size == 3
    error_message = "Node group max_size must match the input variable"
  }
}

run "multiple_node_groups_are_created" {
  command = plan

  variables {
    node_groups = {
      general = {
        instance_types = ["t3.medium"]
        capacity_type  = "ON_DEMAND"
        min_size       = 1
        max_size       = 3
        desired_size   = 2
        disk_size_gb   = 50
        labels         = { role = "general" }
        taints         = []
      }
      spot = {
        instance_types = ["t3.large", "t3a.large"]
        capacity_type  = "SPOT"
        min_size       = 0
        max_size       = 5
        desired_size   = 0
        disk_size_gb   = 50
        labels         = { role = "spot" }
        taints         = []
      }
    }
  }

  assert {
    condition     = length(aws_eks_node_group.this) == 2
    error_message = "Two node groups must be created when two entries are provided"
  }
}
