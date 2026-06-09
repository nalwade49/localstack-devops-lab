resource "aws_iam_user" "team" {
  for_each = var.team_members
  
  # "each.value" represents the current name in the loop
  name     = each.value 
}
