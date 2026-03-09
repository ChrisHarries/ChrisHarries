mock_provider "aws" {}

variables {
  name_prefix                       = "test-dev"
  vpc_id                            = "vpc-12345678"
  subnet_id                         = "subnet-aaa"
  instance_type                     = "t3.small"
  allowed_source_security_group_ids = ["sg-nodes"]
  squid_port                        = 3128
  allowed_domains = [
    ".amazonaws.com",
    ".docker.io",
  ]
}

run "proxy_security_group_is_created" {
  command = plan

  assert {
    condition     = aws_security_group.proxy.name == "test-dev-proxy-sg"
    error_message = "Proxy security group name does not match naming convention"
  }

  assert {
    condition     = aws_security_group.proxy.vpc_id == var.vpc_id
    error_message = "Proxy security group must be in the correct VPC"
  }
}

run "proxy_egress_includes_ipv6" {
  command = plan

  assert {
    condition     = contains(aws_security_group_rule.proxy_egress_https.ipv6_cidr_blocks, "::/0")
    error_message = "Proxy HTTPS egress must include IPv6"
  }

  assert {
    condition     = contains(aws_security_group_rule.proxy_egress_http.ipv6_cidr_blocks, "::/0")
    error_message = "Proxy HTTP egress must include IPv6"
  }
}

run "proxy_instance_uses_imdsv2" {
  command = plan

  assert {
    condition     = aws_instance.proxy.metadata_options[0].http_tokens == "required"
    error_message = "Proxy EC2 instance must use IMDSv2 (http_tokens = required)"
  }
}

run "proxy_instance_does_not_have_public_ip_auto_assigned" {
  command = plan

  assert {
    condition     = aws_instance.proxy.associate_public_ip_address == false
    error_message = "Proxy must not auto-assign a public IP — it uses an explicit EIP"
  }
}

run "proxy_root_volume_is_encrypted" {
  command = plan

  assert {
    condition     = aws_instance.proxy.root_block_device[0].encrypted == true
    error_message = "Proxy root EBS volume must be encrypted"
  }
}

run "proxy_iam_role_has_ssm_policy" {
  command = plan

  assert {
    condition     = aws_iam_role_policy_attachment.proxy_ssm.policy_arn == "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
    error_message = "Proxy IAM role must have SSM access for keyless shell access"
  }
}

run "squid_port_is_configurable" {
  command = plan

  variables {
    squid_port = 8080
  }

  assert {
    condition     = aws_security_group_rule.proxy_ingress_from_sg["sg-nodes"].from_port == 8080
    error_message = "Ingress rule must use the configured squid_port"
  }
}
