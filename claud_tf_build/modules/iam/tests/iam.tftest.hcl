mock_provider "aws" {}

variables {
  name_prefix = "test-dev"
}

run "cluster_role_has_correct_name" {
  command = plan

  assert {
    condition     = aws_iam_role.cluster.name == "test-dev-eks-cluster-role"
    error_message = "Cluster IAM role name does not match the expected naming convention"
  }
}

run "cluster_role_trusted_by_eks" {
  command = plan

  assert {
    condition     = can(jsondecode(aws_iam_role.cluster.assume_role_policy))
    error_message = "Cluster role assume policy must be valid JSON"
  }
}

run "cluster_role_has_required_policy_attachments" {
  command = plan

  assert {
    condition     = aws_iam_role_policy_attachment.cluster_eks_policy.policy_arn == "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
    error_message = "Cluster role must have AmazonEKSClusterPolicy attached"
  }

  assert {
    condition     = aws_iam_role_policy_attachment.cluster_vpc_resource_controller.policy_arn == "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController"
    error_message = "Cluster role must have AmazonEKSVPCResourceController attached"
  }
}

run "node_role_has_correct_name" {
  command = plan

  assert {
    condition     = aws_iam_role.node.name == "test-dev-eks-node-role"
    error_message = "Node IAM role name does not match the expected naming convention"
  }
}

run "node_role_has_required_policy_attachments" {
  command = plan

  assert {
    condition     = aws_iam_role_policy_attachment.node_worker_policy.policy_arn == "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
    error_message = "Node role must have AmazonEKSWorkerNodePolicy attached"
  }

  assert {
    condition     = aws_iam_role_policy_attachment.node_cni_policy.policy_arn == "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
    error_message = "Node role must have AmazonEKS_CNI_Policy attached for VPC CNI"
  }

  assert {
    condition     = aws_iam_role_policy_attachment.node_ecr_readonly.policy_arn == "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
    error_message = "Node role must have ECR read-only access to pull images"
  }

  assert {
    condition     = aws_iam_role_policy_attachment.node_ssm.policy_arn == "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
    error_message = "Node role must have SSM access for shell access without bastion"
  }
}
