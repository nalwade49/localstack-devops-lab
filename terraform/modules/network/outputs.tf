output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.lab_vpc.id
}

output "public_subnet_a_id" {
  description = "ID of public subnet A"
  value       = aws_subnet.public_subnet.id
}

output "private_subnet_a_id" {
  description = "ID of private subnet A"
  value       = aws_subnet.private_subnet.id
}

output "public_subnet_b_id" {
  description = "ID of public subnet B"
  value       = aws_subnet.public_subnet_b.id
}

output "private_subnet_b_id" {
  description = "ID of private subnet B"
  value       = aws_subnet.private_subnet_b.id
}
