variable "team_members" {
  description = "A list of IAM users to create"
  type        = set(string)
  default     = ["alice", "bob", "charlie"]
}
