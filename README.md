# LocalStack DevOps Lab

A self-driven infrastructure lab built after completing CDAC DITISS (Feb 2026), practicing real-world AWS architecture patterns using **Terraform** and **LocalStack Community** — entirely offline, zero cloud cost.

---

## What This Lab Covers

| Layer | What's Built |
|---|---|
| **IaC** | Full Terraform codebase — providers, variables, outputs, resource dependencies |
| **Networking** | Multi-AZ VPC (2 AZs), public/private subnets, IGW, **NAT Gateway**, route tables, NACLs |
| **Compute** | Bastion host, private app server, two web nodes (one per AZ) with `user_data` injection |
| **Load Balancing** | Bastion-hosted **Nginx reverse proxy** load-balancing across both web nodes (DIY ALB — LocalStack Community has no native ALB support) |
| **Security** | Security group chaining (SSH + HTTP scoped to bastion-sg only), least-privilege IAM policies (designed and attached; live enforcement is a known LocalStack Community limitation — see IAM section), S3 object-level access control |
| **Storage** | S3 bucket with tiered access — public read for junior devs, admin-only objects |
| **IAM** | Users via `for_each`, groups, inline + managed policies, group membership |

---

## Architecture

```
                              Internet
                                  │
                                  ▼
┌───────────────────────────────────────────────────────────────────┐
│                        VPC: 10.0.0.0/16                            │
│                                                                     │
│  ┌──────────────────────┐         ┌──────────────────────┐         │
│  │  Public Subnet A      │         │  Public Subnet B      │         │
│  │  10.0.1.0/24          │         │  10.0.3.0/24          │         │
│  │  (us-east-1a)         │         │  (us-east-1b)         │         │
│  │                       │         │                       │         │
│  │  [Bastion Host]       │         │  [NAT Gateway]        │         │
│  │  Nginx reverse proxy  │         │  + Elastic IP         │         │
│  │  SSH:22, HTTP:80      │         │                       │         │
│  └───────────┬───────────┘         └───────────────────────┘         │
│              │ SG Chaining (SSH + HTTP only from bastion-sg)         │
│              │ Nginx proxy_pass → backend_nodes upstream             │
│  ┌───────────▼───────────┐         ┌──────────────────────┐         │
│  │  Private Subnet A      │         │  Private Subnet B      │         │
│  │  10.0.2.0/24           │         │  10.0.4.0/24           │         │
│  │  (us-east-1a)          │         │  (us-east-1b)          │         │
│  │                        │         │                        │         │
│  │  [Private App]         │         │  [Web Node B]          │         │
│  │  [Web Node A]          │         │  Port 80 via           │         │
│  │  Port 80 via           │         │  python http.srv       │         │
│  │  python http.srv       │         │                        │         │
│  └────────────────────────┘         └────────────────────────┘         │
└───────────────────────────────────────────────────────────────────┘
```

**Traffic flow:**
- Public internet → Bastion (SSH port 22, HTTP port 80) via NACL + bastion-sg
- Bastion → Web Node A / Web Node B (port 80 only) via security group chaining — `private_app_sg` accepts port 80 exclusively from `bastion_sg` ID, never from `0.0.0.0/0`. The bastion runs Nginx as a reverse proxy, load-balancing requests across both nodes via an `upstream backend_nodes` block populated with their private IPs at instance launch
- Bastion → Private App (SSH only) via the same chaining pattern — `private_app_sg` accepts port 22 exclusively from `bastion_sg` ID, not a CIDR range
- Private subnets (both AZs) → Internet via the single NAT Gateway in Public Subnet A (outbound only, no inbound path)

---

## Security Group Chaining

The key security design in this lab — `private_app_sg` does not open SSH or HTTP to `0.0.0.0/0` or even to the VPC CIDR. Both ingress rules reference the bastion security group ID directly:

```hcl
ingress {
  from_port       = 22
  to_port         = 22
  protocol        = "tcp"
  security_groups = [aws_security_group.bastion_sg.id]
}

ingress {
  from_port       = 80
  to_port         = 80
  protocol        = "tcp"
  security_groups = [aws_security_group.bastion_sg.id]
}
```

This means even if an attacker reaches the VPC, they cannot SSH or send HTTP traffic to private instances without going through the Bastion — and any instance removed from `bastion_sg` instantly loses both access paths.

---

## DIY Load Balancing — Nginx on the Bastion

LocalStack Community doesn't emulate the ALB resource (it's a Pro-tier feature), so this lab implements the same pattern — a single public entry point distributing traffic across multiple private backends — using Nginx as a reverse proxy on the bastion instead:

```nginx
upstream backend_nodes {
    server <web_node_a_private_ip>;
    server <web_node_b_private_ip>;
}
server {
    listen 80;
    location / {
        proxy_pass http://backend_nodes;
    }
}
```

The backend IPs are injected at instance launch via Terraform string interpolation (`${aws_instance.web_node_a.private_ip}`), so the config is generated fresh from the actual Terraform-managed state rather than hardcoded. Because this is LocalStack Community, the `user_data` script is stored as instance metadata but not executed by a real hypervisor — so this validates the Terraform interpolation and HCL correctness of the pattern, not a running Nginx process. The equivalent on real AWS would swap this block for an `aws_lb` + `aws_lb_target_group` + `aws_lb_listener` resource set, with `alb_sg` replacing `bastion_sg` as the chaining anchor.

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

- Designed to list the bucket — knows it exists
- Designed to read exactly one object — `public-data.txt`
- Designed to be denied `admin-only.txt` at the object level
- Designed to be blocked from writing, deleting, or accessing any other bucket

Users (`alice`, `bob`, `charlie`) are created dynamically using Terraform `for_each` — adding a new team member means editing one variable, not adding a new resource block.

> **Known limitation:** LocalStack Community's `ENFORCE_IAM` flag has inconsistent enforcement upstream — tracked in [localstack/localstack#6173](https://github.com/localstack/localstack/issues/6173) and [#7183](https://github.com/localstack/localstack/issues/7183). In this lab, `alice`'s scoped credentials were tested directly against an action her policy does not grant (`s3:CreateBucket`) with both `ENFORCE_IAM=1` and `IAM_SOFT_MODE=1` set, and the action succeeded rather than being denied or logged as a violation. The policy itself is correctly written and attached (verifiable via `awslocal iam list-attached-user-policies --user-name alice`), but live deny-behavior could not be reproduced in Community edition on this version. This is a platform constraint, not a flaw in the Terraform policy logic.

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
# Confirm alice's policy is attached as designed
awslocal iam list-attached-user-policies --user-name alice

# Alice can list the vault and read the public file (works as designed)
awslocal s3 ls s3://raj-secure-vault/ --profile alice
awslocal s3 cp s3://raj-secure-vault/public-data.txt - --profile alice

# Alice attempting an out-of-scope action (e.g. s3:CreateBucket, which her
# policy does not grant) — on real AWS or a fully enforcing LocalStack
# Pro/Ultimate setup this returns AccessDenied. On LocalStack Community
# 4.4.0 this currently succeeds due to the ENFORCE_IAM limitation noted above.
awslocal s3 mb s3://should-be-denied-for-alice --profile alice
```

---

## LocalStack Scope

This lab uses **LocalStack Community**, which simulates the AWS control plane — API calls, resource state, IAM logic, S3 operations. EC2 instances exist as state records; `user_data` scripts are stored in metadata but not executed (no hypervisor layer in Community edition).

What this validates:
- Terraform HCL correctness and resource dependency graph
- Network topology — subnet placement, route table associations, NACL rules
- Security group chaining logic (SSH and HTTP scoped to bastion-sg)
- Nginx config interpolation against live Terraform-managed private IPs
- IAM policy authorship and attachment (structurally correct, least-privilege scoped)
- S3 bucket and object structure

What it does *not* validate in Community edition: live IAM deny-enforcement (see Known Limitation above) and EC2 `user_data` execution (no real hypervisor backing instances).

---

## Tech Stack

- **Terraform** `hashicorp/aws v6.49.0`
- **LocalStack Community** (Docker)
- **AWS CLI** via `awslocal` wrapper
- **Bash** — init scripts and automated git backup via cron

---
## Status

Active — ongoing self-driven learning post-CDAC. Terraform modules, data sources, and remote state management in progress.
