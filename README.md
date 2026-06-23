# LocalStack DevOps Lab

A self-driven infrastructure lab built after completing CDAC DITISS (Feb 2026), practicing real-world AWS architecture patterns using **Terraform** and **LocalStack Community** — entirely offline, zero cloud cost.

---

## What This Lab Covers

| Layer | What's Built |
|---|---|
| **IaC** | Modular Terraform codebase — reusable network and compute modules, variables, outputs, data sources, remote state with S3 backend, native state locking, bootstrap pattern |
| **Networking** | Multi-AZ VPC (2 AZs), public/private subnets, IGW, **NAT Gateway**, route tables, NACLs, dynamic AZ resolution via data source |
| **Compute** | Bastion host, private app server, two web nodes (one per AZ) with `user_data` injection |
| **Load Balancing** | Bastion-hosted **Nginx reverse proxy** load-balancing across both web nodes (DIY ALB — LocalStack Community has no native ALB support) |
| **Security** | Security group chaining (SSH + HTTP scoped to bastion-sg only), least-privilege IAM policies, S3 object-level access control, `prevent_destroy` on foundational infrastructure |
| **Storage** | S3 bucket with tiered access — public read for junior devs, admin-only objects. Remote state bucket with versioning and native S3 lock file support |
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
- Bastion → Web Node A / Web Node B (port 80 only) via security group chaining — `private_app_sg` accepts port 80 exclusively from `bastion_sg` ID, never from `0.0.0.0/0`
- Bastion → Private App (SSH only) via the same chaining pattern — `private_app_sg` accepts port 22 exclusively from `bastion_sg` ID, not a CIDR range
- Private subnets (both AZs) → Internet via the single NAT Gateway in Public Subnet A (outbound only, no inbound path)

---

## Terraform Modules

Network and compute resources are organized into reusable modules under `modules/`. Each module is self-contained with its own `variables.tf`, `main.tf`, and `outputs.tf`.

```
modules/
├── network/          # VPC, subnets, IGW, NAT, route tables, NACLs
│   ├── variables.tf  # vpc_cidr, subnet CIDRs, name_prefix
│   ├── main.tf       # All networking resources + AZ data source
│   └── outputs.tf    # vpc_id, subnet IDs passed to compute module
└── compute/          # Security groups, EC2 instances
    ├── variables.tf  # ami, instance_type, vpc_id, subnet IDs from network
    ├── main.tf       # SG chaining, bastion, web nodes, private app
    └── outputs.tf    # bastion_public_ip, instance IDs
```

The root `main.tf` wires them together, passing network outputs into compute inputs:

``` hcl
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
```

To deploy a second environment, pass different CIDRs and a different `name_prefix` — no code changes needed, only variable values.

---

## Dynamic AZ Resolution

Availability zones are resolved dynamically via a data source instead of hardcoded strings:

``` hcl
data "aws_availability_zones" "available" {
  state = "available"
}

availability_zone = data.aws_availability_zones.available.names[0]  # us-east-1a
availability_zone = data.aws_availability_zones.available.names[1]  # us-east-1b
```

Makes the module portable across regions without editing configuration.

---

## Remote State and Locking

Terraform state is stored in an S3 backend (`raj-tf-state`) with versioning enabled. Native S3 locking (`use_lockfile = true`, GA in Terraform 1.11) is used instead of the deprecated DynamoDB-based locking pattern.

**How locking works:** Terraform writes a `.tflock` object to S3 before any state-touching operation. A concurrent `apply` from a second developer fails immediately with a lock conflict error until the first operation completes and deletes the lock file.

**Verified on LocalStack 4.4.0:**

``` bash
awslocal s3api list-object-versions --bucket raj-tf-state
# Shows terraform.tfstate (IsLatest: true)
# Shows terraform.tfstate.tflock with a DeleteMarker (IsLatest: true)
# Confirms: lock acquired → operation completed → lock released
```

### Bootstrap Pattern

The `raj-tf-state` bucket is provisioned by a separate, minimal Terraform config in `bootstrap/` that runs on local state — solving the chicken-and-egg problem of needing a bucket to store state before Terraform can create it.

```
bootstrap/    ← runs once, local state only, creates the shared backend bucket
terraform/    ← all projects store state inside that bucket via key isolation
```

The bootstrap bucket has `prevent_destroy = true` to guard against accidental `terraform destroy` wiping every project's state simultaneously:

``` hcl
resource "aws_s3_bucket" "tf_state" {
  bucket = "raj-tf-state"

  lifecycle {
    prevent_destroy = true
  }
}
```

> **Why prevent_destroy here and nowhere else:** Bootstrap's bucket is the one resource where a destroy in one directory has blast radius across every other project's state. Main project resources (VPC, EC2, IAM) are designed to be rebuilt freely. The lifecycle block is placed exactly where the cross-project dependency is real but invisible to Terraform's own graph.

> **LocalStack constraint:** LocalStack Community Edition does not persist data across container restarts — persistence is a Pro-only feature. The remote state pattern is fully demonstrated and correct; the constraint is a platform limitation, not a design flaw. On real AWS this setup provides genuine cross-session and cross-developer durability.

---

## Security Group Chaining

`private_app_sg` does not open SSH or HTTP to `0.0.0.0/0` or even to the VPC CIDR. Both ingress rules reference the bastion security group ID directly:

``` hcl
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

Even if an attacker reaches the VPC, they cannot SSH or send HTTP to private instances without going through the bastion — and any instance removed from `bastion_sg` instantly loses both access paths.

---

## DIY Load Balancing — Nginx on the Bastion

LocalStack Community doesn't emulate ALB (Pro-tier feature). This lab implements the same pattern using Nginx as a reverse proxy on the bastion:

``` nginx
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

Backend IPs are injected at instance launch via Terraform string interpolation. On real AWS this block swaps for `aws_lb` + `aws_lb_target_group` + `aws_lb_listener`.

---

## IAM — Least Privilege Design

**alice** (junior dev) gets the minimum necessary:

``` json
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

Users (`alice`, `bob`, `charlie`) are created dynamically using Terraform `for_each` — adding a new team member means editing one variable, not adding a new resource block.

> **Known limitation:** LocalStack Community's IAM enforcement has inconsistent behavior — tracked in [localstack/localstack#6173](https://github.com/localstack/localstack/issues/6173). The policy is correctly written and attached (verifiable via `awslocal iam list-attached-user-policies --user-name alice`), but live deny-behavior could not be reproduced in Community edition on this version. This is a platform constraint, not a flaw in the Terraform policy logic.

---

## NACL — Stateless Perimeter Rules

Unlike security groups, NACLs are stateless — return traffic must be explicitly allowed:

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
│   ├── bootstrap/
│   │   └── main.tf           # One-time S3 backend bucket provisioning (local state)
│   ├── modules/
│   │   ├── network/
│   │   │   ├── main.tf       # VPC, subnets, IGW, NAT, route tables, NACLs
│   │   │   ├── variables.tf  # Input variables (CIDRs, name_prefix)
│   │   │   └── outputs.tf    # vpc_id, subnet IDs
│   │   └── compute/
│   │       ├── main.tf       # Security groups, EC2 instances
│   │       ├── variables.tf  # Input variables (ami, instance_type, subnet IDs)
│   │       └── outputs.tf    # bastion_public_ip, instance IDs
│   ├── providers.tf          # Backend config, provider config, version pin (6.49.0)
│   ├── variables.tf          # IAM team members, legacy sync config
│   ├── main.tf               # Module calls, IAM, S3 resources
│   └── output.tf             # User ARNs, vpc_id, bastion_public_ip
├── init-scripts/
│   └── setup.sh              # Day 1-2 CLI-based setup (pre-Terraform phase)
├── .gitignore                # Excludes .tfstate, .terraform/, .tfvars
└── docker-compose.yaml       # LocalStack service definition (pinned 4.4.0)
```

---

## How to Run

**Prerequisites:** Docker, Terraform >= 1.15, `awslocal` CLI wrapper

``` bash
# Start LocalStack
docker-compose up -d

# Confirm LocalStack is ready
awslocal ec2 describe-availability-zones

# Step 1: Bootstrap — run once to create remote state bucket
cd terraform/bootstrap/
terraform init
terraform apply

# Verify bucket exists
awslocal s3 ls s3://raj-tf-state/

# Step 2: Init main project
cd ../
terraform init

# Step 3: Apply
terraform apply --auto-approve

# Verify resources
awslocal ec2 describe-instances \
  --query 'Reservations[*].Instances[*].[InstanceId,Tags[0].Value,State.Name]' \
  --output table
awslocal iam list-users
awslocal s3 ls s3://raj-secure-vault/

# Verify remote state and lock history
awslocal s3 ls s3://raj-tf-state/ --recursive
awslocal s3api list-object-versions --bucket raj-tf-state
```

---

## Verify IAM Least Privilege

``` bash
# Confirm alice's policy is attached
awslocal iam list-attached-user-policies --user-name alice

# Alice can list and read the public file (works as designed)
awslocal s3 ls s3://raj-secure-vault/ --profile alice
awslocal s3 cp s3://raj-secure-vault/public-data.txt - --profile alice

# Alice attempting an out-of-scope action — AccessDenied on real AWS
# Succeeds on LocalStack Community 4.4.0 due to IAM enforcement limitation
awslocal s3 mb s3://should-be-denied-for-alice --profile alice
```

---

## LocalStack Scope

This lab uses **LocalStack Community**, which simulates the AWS control plane. EC2 instances exist as state records; `user_data` scripts are stored in metadata but not executed (no hypervisor in Community edition). Data does not persist across container restarts (persistence is a Pro-only feature).

What this validates:
- Terraform HCL correctness and module structure
- Remote state and native S3 locking pattern (Terraform 1.11+)
- Bootstrap pattern for chicken-and-egg state bucket provisioning
- Network topology — subnet placement, route tables, NACLs
- Security group chaining logic (SSH and HTTP scoped to bastion-sg)
- Nginx config interpolation against live Terraform-managed private IPs
- IAM policy authorship and attachment (structurally correct, least-privilege scoped)
- S3 bucket and object structure
- Dynamic AZ resolution via data source

What it does *not* validate in Community edition: live IAM deny-enforcement and EC2 `user_data` execution.

---

## Tech Stack

- **Terraform** `hashicorp/aws v6.49.0`
- **LocalStack Community** `4.4.0` (Docker, pinned — pre-auth-token requirement)
- **AWS CLI** via `awslocal` wrapper
- **Bash** — init scripts and automated git backup via cron

---

## Status

Complete — modules, remote state, native S3 locking, bootstrap pattern, dynamic AZ resolution, and `prevent_destroy` all implemented and verified on LocalStack 4.4.0.
