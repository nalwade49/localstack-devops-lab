output "all_user_arns" {
  value = [for user in aws_iam_user.team : user.arn]
}

output "vpc_id" {
  description = "VPC ID from network module"
  value       = module.network.vpc_id
}

output "bastion_public_ip" {
  description = "Public IP of bastion host"
  value       = module.compute.bastion_public_ip
}
