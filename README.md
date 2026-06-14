# LocalStack DevOps Lab

A self-driven infrastructure lab built after completing CDAC DITISS (Feb 2026), practicing real-world AWS architecture patterns using **Terraform** and **LocalStack Community** — entirely offline, zero cloud cost.

---

## What This Lab Covers

| Layer | What's Built |
|---|---|
| **IaC** | Full Terraform codebase — providers, variables, outputs, resource dependencies |
| **Networking** | Multi-AZ VPC, public/private subnets, IGW, NAT Gateway, route tables, NACLs |
| **Compute** | Bastion host, private app server, two web nodes with user_data injection |
| **Security** | Security group chaining, least-privilege IAM, S3 object-level access control |
| **Storage** | S3 bucket with tiered access — public read for junior devs, admin-only objects |
| **IAM** | Users via `for_each`, groups, inline + managed policies, group membership |

---

## Architecture

```
Internet
    │
    ▼
┌─────────────────────────────────────────────────────┐
│                   VPC: 10.0.0.0/16                  │
│                                                     │
│  ┌──────────────────┐   ┌──────────────────┐        │
│  │  Public Subnet A │   │  Public Subnet B │        │
│  │  10.0.1.0/24     │   │  10.0.3.0/24     │        │
│  │  (us-east-1a)    │   │  (us-east-1b)    │        │
│  │                  │   │                  │        │
│  │  [Bastion Host]  │   │  [NAT Gateway]   │        │
│  │  raj-bastion-sg  │   │  + Elastic IP    │        │
│  │  SSH:22, HTTP:80 │   │                  │        │
│  └────────┬─────────┘   └──────────────────┘        │
│           │ SG Chaining (SSH only from bastion-sg)  │
│  ┌────────▼─────────┐   ┌──────────────────┐        │
│  │  Private Subnet A│   │  Private Subnet B│        │
│  │  10.0.2.0/24     │   │  10.0.4.0/24     │        │
│  │  (us-east-1a)    │   │  (us-east-1b)    │        │
│  │                  │   │                  │        │
│  │  [Private App]   │   │  [Web Node B]    │        │
│  │  [Web Node A]    │   │  Port 80 via     │        │
│  │  Port 80 via     │   │  python http.srv │        │
│  │  python http.srv │   │                  │        │
│  └──────────────────┘   └──────────────────┘        │
└─────────────────────────────────────────────────────┘
```

**Traffic flow:**
- Public internet → Bastion (SSH port 22, HTTP port 80) via NACL + bastion-sg
- Bastion → Private App (SSH only) via security group chaining — `private_app_sg` accepts port 22 exclusively from `bastion_sg` ID, not a CIDR range
- ALB-sg → Private App (port 80) — backend nodes only reachable from ALB security group
- Private subnets → Internet via NAT Gateway (outbound only, no inbound path)

---

## Security Group Chaining

The key security design in this lab — `private_app_sg` does not open SSH to `0.0.0.0/0` or even to the VPC CIDR. It references the bastion security group ID directly:

```hcl
ingress {
  from_port       = 22
  to_port         = 22
  protocol        = "tcp"
  security_groups = [aws_security_group.bastion_sg.id]
}
```

This means even if an attacker reaches the VPC, they cannot SSH to private instances without going through the Bastion — and any instance removed from `bastion_sg` instantly loses that access.

---

## IAM — Least Privilege Design

**alice** (junior dev) gets the minimum necessary:

```json
{
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["s3:ListBucket"],
      "Resource": "arn:aws:s3:::raj-secure-vault"
    },
    {
      "Effect": "Allow",
      "Action": ["s3:GetObject"],
      "Resource": "arn:aws:s3:::raj-secure-vault/public-data.txt"
    }
  ]
}
```

- Can list the bucket — knows it exists
- Can read exactly one object — `public-data.txt`
- Cannot read `admin-only.txt` — access denied at object level
- Cannot write, delete, or access any other bucket

Users (`alice`, `bob`, `charlie`) are created dynamically using Terraform `for_each` — adding a new team member means editing one variable, not adding a new resource block.

---

## NACL — Stateless Perimeter Rules

Unlike security groups, NACLs are stateless — return traffic must be explicitly allowed. The public NACL handles this:

| Direction | Rule | Port | Reason |
|---|---|---|---|
| Inbound | 100 | 22 | SSH to Bastion |
| Inbound | 110 | 1024–65535 | Ephemeral return traffic from internet |
| Outbound | 100 | 1024–65535 | Response traffic back to clients |
| Outbound | 110 | 80 | HTTP for package updates |
| Outbound | 120 | 443 | HTTPS for package updates |

---

## Project Structure

```
localstack-devops-lab/
├── terraform/
│   ├── providers.tf      # LocalStack endpoint config, mock credentials
│   ├── variables.tf      # Team members, admin users, legacy sync object
│   ├── main.tf           # IAM users, groups, policies, S3 resources
│   ├── network.tf        # VPC, subnets, IGW, NAT, route tables, NACLs
│   └── compute.tf        # Security groups, EC2 instances, SG chaining
├── init-scripts/
│   └── setup.sh          # Day 1-2 CLI-based setup (pre-Terraform phase)
├── .gitignore            # Excludes .tfstate, .terraform/, .tfvars
└── docker-compose.yaml   # LocalStack service definition
```

---

## How to Run

**Prerequisites:** Docker, Terraform, `awslocal` CLI wrapper

```bash
# Start LocalStack
docker-compose up -d

# Confirm LocalStack is ready
awslocal ec2 describe-availability-zones

# Init and apply Terraform
cd terraform/
terraform init
terraform apply --auto-approve

# Verify resources
awslocal ec2 describe-instances --query 'Reservations[*].Instances[*].[InstanceId,Tags[0].Value,State.Name]' --output table
awslocal iam list-users
awslocal s3 ls s3://raj-secure-vault/
```

---

## Verify IAM Least Privilege

```bash
# Alice can list the vault
awslocal s3 ls s3://raj-secure-vault/ --profile alice

# Alice can read the public file
awslocal s3 cp s3://raj-secure-vault/public-data.txt - --profile alice

# Alice cannot read admin-only content (expect AccessDenied)
awslocal s3 cp s3://raj-secure-vault/admin-only.txt - --profile alice
```

---

## LocalStack Scope

This lab uses **LocalStack Community**, which simulates the AWS control plane — API calls, resource state, IAM logic, S3 operations. EC2 instances exist as state records; `user_data` scripts are stored in metadata but not executed (no hypervisor layer in Community edition).

What this validates:
- Terraform HCL correctness and resource dependency graph
- Network topology — subnet placement, route table associations, NACL rules
- Security group chaining logic
- IAM policy evaluation and least-privilege enforcement
- S3 bucket and object-level access boundaries

---

## Tech Stack

- **Terraform** `hashicorp/aws v6.49.0`
- **LocalStack Community** (Docker)
- **AWS CLI** via `awslocal` wrapper
- **Bash** — init scripts and automated git backup via cron

---
## Status

Active — ongoing self-driven learning post-CDAC. Terraform modules, data sources, and remote state management in progress.
