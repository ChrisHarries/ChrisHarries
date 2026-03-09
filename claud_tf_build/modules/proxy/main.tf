# ------------------------------------------------------------------
# Latest Amazon Linux 2023 AMI
# ------------------------------------------------------------------
data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# ------------------------------------------------------------------
# IAM role (SSM access — no SSH key needed)
# ------------------------------------------------------------------
data "aws_iam_policy_document" "proxy_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "proxy" {
  name               = "${var.name_prefix}-proxy-role"
  assume_role_policy = data.aws_iam_policy_document.proxy_assume_role.json

  tags = { Name = "${var.name_prefix}-proxy-role" }
}

resource "aws_iam_role_policy_attachment" "proxy_ssm" {
  role       = aws_iam_role.proxy.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "proxy" {
  name = "${var.name_prefix}-proxy-profile"
  role = aws_iam_role.proxy.name
}

# ------------------------------------------------------------------
# Security Group
# ------------------------------------------------------------------
resource "aws_security_group" "proxy" {
  name        = "${var.name_prefix}-proxy-sg"
  description = "Squid proxy — accepts traffic from nodes, sends out to internet"
  vpc_id      = var.vpc_id

  tags = { Name = "${var.name_prefix}-proxy-sg" }
}

# Allow nodes (by SG) to reach the proxy port
resource "aws_security_group_rule" "proxy_ingress_from_sg" {
  for_each = toset(var.allowed_source_security_group_ids)

  description              = "Allow traffic from ${each.value} to proxy port"
  type                     = "ingress"
  from_port                = var.squid_port
  to_port                  = var.squid_port
  protocol                 = "tcp"
  security_group_id        = aws_security_group.proxy.id
  source_security_group_id = each.value
}

# Allow CIDR sources to reach the proxy port (optional fallback)
resource "aws_security_group_rule" "proxy_ingress_from_cidr" {
  count = length(var.allowed_source_cidrs) > 0 ? 1 : 0

  description       = "Allow CIDR sources to reach proxy port"
  type              = "ingress"
  from_port         = var.squid_port
  to_port           = var.squid_port
  protocol          = "tcp"
  cidr_blocks       = var.allowed_source_cidrs
  security_group_id = aws_security_group.proxy.id
}

resource "aws_security_group_rule" "proxy_egress_https" {
  description        = "Allow proxy to make outbound HTTPS requests"
  type               = "egress"
  from_port          = 443
  to_port            = 443
  protocol           = "tcp"
  cidr_blocks        = ["0.0.0.0/0"]
  ipv6_cidr_blocks   = ["::/0"]
  security_group_id  = aws_security_group.proxy.id
}

resource "aws_security_group_rule" "proxy_egress_http" {
  description        = "Allow proxy to make outbound HTTP requests"
  type               = "egress"
  from_port          = 80
  to_port            = 80
  protocol           = "tcp"
  cidr_blocks        = ["0.0.0.0/0"]
  ipv6_cidr_blocks   = ["::/0"]
  security_group_id  = aws_security_group.proxy.id
}

# ------------------------------------------------------------------
# Elastic IP (stable outbound IP for external allowlisting)
# ------------------------------------------------------------------
resource "aws_eip" "proxy" {
  domain = "vpc"
  tags   = { Name = "${var.name_prefix}-proxy-eip" }
}

resource "aws_eip_association" "proxy" {
  instance_id   = aws_instance.proxy.id
  allocation_id = aws_eip.proxy.id
}

# ------------------------------------------------------------------
# Squid configuration rendered from allowed_domains variable
# ------------------------------------------------------------------
locals {
  squid_acl_lines = join("\n", [
    for domain in var.allowed_domains :
    "acl allowed_domains dstdomain ${domain}"
  ])

  squid_conf = <<-SQUID
    # Squid configuration managed by Terraform — do not edit manually

    http_port ${var.squid_port}

    # --- Domain allowlist ---
    ${local.squid_acl_lines}

    http_access allow allowed_domains
    http_access deny all

    # Recommended performance/safety settings
    forwarded_for delete
    via off
    request_header_access X-Forwarded-For deny all

    coredump_dir /var/spool/squid
    refresh_pattern . 0 20% 4320
  SQUID
}

# ------------------------------------------------------------------
# EC2 Instance
# ------------------------------------------------------------------
resource "aws_instance" "proxy" {
  ami                    = data.aws_ami.al2023.id
  instance_type          = var.instance_type
  subnet_id              = var.subnet_id
  iam_instance_profile   = aws_iam_instance_profile.proxy.name
  vpc_security_group_ids = [aws_security_group.proxy.id]

  # Do not assign auto public IP — we attach an EIP explicitly
  associate_public_ip_address = false

  user_data = base64encode(<<-EOF
    #!/bin/bash
    set -euo pipefail

    # Install Squid
    dnf install -y squid

    # Write configuration
    cat > /etc/squid/squid.conf << 'SQUIDCONF'
    ${local.squid_conf}
    SQUIDCONF

    # Enable and start
    systemctl enable --now squid

    # Allow systemd to restart on failure
    mkdir -p /etc/systemd/system/squid.service.d
    cat > /etc/systemd/system/squid.service.d/restart.conf << 'UNIT'
    [Service]
    Restart=on-failure
    RestartSec=5s
    UNIT
    systemctl daemon-reload
  EOF
  )

  metadata_options {
    http_tokens = "required" # IMDSv2 only
  }

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 20
    encrypted             = true
    kms_key_id            = var.kms_key_id
    delete_on_termination = true
  }

  tags = { Name = "${var.name_prefix}-squid-proxy" }

  lifecycle {
    # Replacing the instance recreates the EIP association — plan carefully
    create_before_destroy = false
  }
}
