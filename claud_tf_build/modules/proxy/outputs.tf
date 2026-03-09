output "proxy_security_group_id" {
  description = "Security group ID of the proxy instance"
  value       = aws_security_group.proxy.id
}

output "proxy_private_ip" {
  description = "Private IP address of the proxy instance"
  value       = aws_instance.proxy.private_ip
}

output "proxy_public_ip" {
  description = "Public (EIP) of the proxy instance — use for egress allowlisting"
  value       = aws_eip.proxy.public_ip
}

output "proxy_url" {
  description = "HTTP proxy URL to set in HTTP_PROXY / HTTPS_PROXY environment variables"
  value       = "http://${aws_instance.proxy.private_ip}:${var.squid_port}"
}
