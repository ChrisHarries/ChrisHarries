# ------------------------------------------------------------------
# Launch Template per node group
# Enforces IMDSv2 (http_tokens=required) and sets the IMDS hop limit
# to 1, which prevents pods from reaching the instance metadata
# service. Also moves EBS configuration here so we can use a CMK.
#
# NOTE: When using a launch template, disk_size cannot be set directly
# on the managed node group — it must be set in block_device_mappings.
# ------------------------------------------------------------------
resource "aws_launch_template" "node" {
  for_each = var.node_groups

  name_prefix = "${var.name_prefix}-${each.key}-"
  description = "Launch template for EKS managed node group ${var.name_prefix}-${each.key}"

  # Do NOT set image_id or instance_type here — let the managed node group
  # select the correct EKS-optimised AMI and honour instance_types below.

  metadata_options {
    http_tokens                 = "required" # IMDSv2 only — disables legacy IMDSv1
    http_put_response_hop_limit = 1          # Blocks pod-level IMDS access
    http_endpoint               = "enabled"
  }

  block_device_mappings {
    # Amazon EKS AL2 and AL2023 AMIs use /dev/xvda as the root device.
    device_name = "/dev/xvda"

    ebs {
      volume_size           = each.value.disk_size_gb
      volume_type           = "gp3"
      encrypted             = true
      kms_key_id            = var.kms_key_id
      delete_on_termination = true
    }
  }

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "${var.name_prefix}-${each.key}-node"
    }
  }

  tag_specifications {
    resource_type = "volume"
    tags = {
      Name = "${var.name_prefix}-${each.key}-node-vol"
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_eks_node_group" "this" {
  for_each = var.node_groups

  cluster_name    = var.cluster_name
  node_group_name = "${var.name_prefix}-${each.key}"
  node_role_arn   = var.node_role_arn
  subnet_ids      = var.subnet_ids

  instance_types = each.value.instance_types
  capacity_type  = each.value.capacity_type
  # disk_size is intentionally omitted — managed via the launch template
  # block_device_mappings above to support CMK encryption and IMDSv2.

  launch_template {
    id      = aws_launch_template.node[each.key].id
    version = aws_launch_template.node[each.key].latest_version
  }

  scaling_config {
    min_size     = each.value.min_size
    max_size     = each.value.max_size
    desired_size = each.value.desired_size
  }

  update_config {
    max_unavailable = 1
  }

  labels = each.value.labels

  dynamic "taint" {
    for_each = each.value.taints
    content {
      key    = taint.value.key
      value  = taint.value.value
      effect = taint.value.effect
    }
  }

  tags = {
    Name = "${var.name_prefix}-${each.key}"
  }

  lifecycle {
    ignore_changes = [scaling_config[0].desired_size]
  }
}
