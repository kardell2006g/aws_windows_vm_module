output "instance_id" {
  value = aws_instance.this.id
}

output "server_type" {
  value = var.server_type
}

output "instance_type" {
  value = aws_instance.this.instance_type
}

output "public_ip" {
  description = "Connect with RDP to this address on port 3389."
  value       = aws_instance.this.public_ip
}

output "private_ip" {
  value = aws_instance.this.private_ip
}

output "subnet_id" {
  value = aws_instance.this.subnet_id
}

output "web_url" {
  description = "NLB URL for Web servers; null for other server types."
  value       = local.is_web ? "http://${aws_lb.web[0].dns_name}:8080" : null
}
