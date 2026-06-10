# --- New Infrastructure Inputs ---
variable "team_members" {
  type        = set(string)
  default     = ["alice", "bob", "charlie"]
}

variable "admin_users" {
  type        = set(string)
  default     = []
}

# --- Legacy Infrastructure Inputs (Liftoff!) ---
variable "legacy_sync" {
  type = object({
    username    = string
    group_name  = string
    policy_name = string
    vault_bucket_arn = string
  })
  default = {
    username    = "alice"
    group_name  = "junior-dev"
    policy_name = "Alice-Strict-S3-Policy"
    vault_bucket_arn = "arn:aws:s3:::raj-secure-vault"
  }
}
