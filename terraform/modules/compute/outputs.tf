output "bastion_public_ip" {
  description = "Public IP of the bastion host"
  value       = aws_instance.bastion.public_ip
}

output "bastion_id" {
  description = "Instance ID of the bastion host"
  value       = aws_instance.bastion.id
}

output "web_node_a_id" {
  description = "Instance ID of web node A"
  value       = aws_instance.web_node_a.id
}

output "web_node_b_id" {
  description = "Instance ID of web node B"
  value       = aws_instance.web_node_b.id
}
