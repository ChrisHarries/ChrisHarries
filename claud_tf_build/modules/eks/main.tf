# EKS Cluster
resource "aws_eks_cluster" "this" {
  name     = "${var.name_prefix}-eks"
  version  = var.cluster_version
  role_arn = var.cluster_role_arn

  vpc_config {
    subnet_ids              = var.subnet_ids
    security_group_ids      = [var.cluster_security_group_id]
    endpoint_public_access  = var.cluster_endpoint_public_access
    endpoint_private_access = true
    public_access_cidrs     = var.cluster_endpoint_public_access_cidrs
  }

  kubernetes_network_config {
    ip_family = var.ip_family
  }

  enabled_cluster_log_types = var.cluster_log_types

  tags = {
    Name = "${var.name_prefix}-eks"
  }
}

# CloudWatch Log Group for control plane logs
resource "aws_cloudwatch_log_group" "eks" {
  name              = "/aws/eks/${var.name_prefix}-eks/cluster"
  retention_in_days = var.log_retention_days
  # CMK encryption: every decrypt call produces a CloudTrail entry so access
  # to audit logs is itself auditable. The key policy must include the
  # logs.<region>.amazonaws.com service principal (granted in the account stack).
  kms_key_id = var.kms_key_id

  tags = {
    Name = "${var.name_prefix}-eks-logs"
  }
}

# OIDC Provider (required for IAM Roles for Service Accounts / IRSA)
data "tls_certificate" "eks_oidc" {
  url = aws_eks_cluster.this.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "this" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks_oidc.certificates[0].sha1_fingerprint]
  url             = aws_eks_cluster.this.identity[0].oidc[0].issuer

  tags = {
    Name = "${var.name_prefix}-eks-oidc"
  }
}

# EKS Add-ons — versions are pinned via variables so upgrades are intentional.
# Update the variable defaults in variables.tf to change versions across all clusters.
resource "aws_eks_addon" "coredns" {
  cluster_name  = aws_eks_cluster.this.name
  addon_name    = "coredns"
  addon_version = var.addon_version_coredns

  depends_on = [aws_eks_cluster.this]
}

resource "aws_eks_addon" "kube_proxy" {
  cluster_name  = aws_eks_cluster.this.name
  addon_name    = "kube-proxy"
  addon_version = var.addon_version_kube_proxy

  depends_on = [aws_eks_cluster.this]
}

resource "aws_eks_addon" "vpc_cni" {
  cluster_name  = aws_eks_cluster.this.name
  addon_name    = "vpc-cni"
  addon_version = var.addon_version_vpc_cni

  depends_on = [aws_eks_cluster.this]
}

resource "aws_eks_addon" "eks_pod_identity_agent" {
  cluster_name  = aws_eks_cluster.this.name
  addon_name    = "eks-pod-identity-agent"
  addon_version = var.addon_version_pod_identity_agent

  depends_on = [aws_eks_cluster.this]
}
