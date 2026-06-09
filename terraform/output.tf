output "all_user_arns" {
  # This loops through the created users and extracts just their ARNs
  value = [for user in aws_iam_user.team : user.arn]
}
