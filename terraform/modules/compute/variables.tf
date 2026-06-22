variable "ami" {
  description = "AMI ID for EC2 instances"
  type        = string
  default     = "ami-df5dbbf0"
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t2.micro"
}

variable "name_prefix" {
  description = "Prefix for all resource name tags"
  type        = string
  default     = "raj"
}

variable "vpc_id" {
  description = "VPC ID from network module"
  type        = string
}

variable "public_subnet_id" {
  description = "Public subnet ID for bastion host"
  type        = string
}

variable "private_subnet_a_id" {
  description = "Private subnet A ID for app server and web node A"
  type        = string
}

variable "private_subnet_b_id" {
  description = "Private subnet B ID for web node B"
  type        = string
}
