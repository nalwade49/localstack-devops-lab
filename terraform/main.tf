module "network" {
  source      = "./modules/network"
  name_prefix = "raj"
}

module "compute" {
  source              = "./modules/compute"
  vpc_id              = module.network.vpc_id
  public_subnet_id    = module.network.public_subnet_a_id
  private_subnet_a_id = module.network.private_subnet_a_id
  private_subnet_b_id = module.network.private_subnet_b_id
}

# Dynamic User Creation
resource "aws_iam_user" "team" {
  for_each = var.team_members
  name     = each.value
}

resource "aws_iam_user" "admins" {
  for_each = var.admin_users
  name     = each.value
}

resource "aws_iam_group" "admin_group" {
  name = "admin-team"
}

resource "aws_iam_group_membership" "admin_membership" {
  name  = "admin-team-membership"
  group = aws_iam_group.admin_group.name
  users = [for u in aws_iam_user.admins : u.name]
}

resource "aws_iam_group_policy_attachment" "admin_policy_attach" {
  group      = aws_iam_group.admin_group.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

resource "aws_iam_group" "legacy_junior_dev" {
  name = var.legacy_sync.group_name
}

resource "aws_iam_group_membership" "legacy_junior_dev_membership" {
  name  = "${var.legacy_sync.group_name}-membership"
  group = aws_iam_group.legacy_junior_dev.name
  users = [var.legacy_sync.username]
}

resource "aws_iam_policy" "legacy_alice_policy" {
  name = var.legacy_sync.policy_name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = var.legacy_sync.vault_bucket_arn
      },
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject"]
        Resource = "${var.legacy_sync.vault_bucket_arn}/public-data.txt"
      }
    ]
  })
}

resource "aws_iam_user_policy_attachment" "legacy_alice_attachment" {
  user       = var.legacy_sync.username
  policy_arn = aws_iam_policy.legacy_alice_policy.arn
}

resource "aws_s3_bucket" "vault" {
  bucket = "raj-secure-vault"
}

resource "aws_s3_object" "public_file" {
  bucket       = aws_s3_bucket.vault.id
  key          = "public-data.txt"
  content      = "Welcome to the secure vault. This is public data accessible by junior devs."
  content_type = "text/plain"
}
