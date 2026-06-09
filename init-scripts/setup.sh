#!/bin/bash
echo "========================================="
echo "Initializing Cloud Infrastructure Lab..."
echo "========================================="

# -------------------------------------------------------------
# IAM - Day 1 (Production-Grade Security & Least Privilege)
# -------------------------------------------------------------
echo "Configuring IAM Entities..."

awslocal iam create-group --group-name junior-dev
awslocal iam create-user --user-name alice
awslocal iam add-user-to-group --group-name junior-dev --user-name alice

# Strict Policy targeting specific bucket resources explicitly
cat > /tmp/junior-dev-policy.json << 'POLICY'
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": ["s3:ListBucket"],
            "Resource": [
                "arn:aws:s3:::raj-local-storage",
                "arn:aws:s3:::raj-secure-vault"
            ]
        },
        {
            "Effect": "Allow",
            "Action": ["s3:GetObject"],
            "Resource": [
                "arn:aws:s3:::raj-local-storage/*",
                "arn:aws:s3:::raj-secure-vault/public-data.txt"
            ]
        }
    ]
}
POLICY

awslocal iam create-policy \
    --policy-name Junior-dev-policy \
    --policy-document file:///tmp/junior-dev-policy.json

awslocal iam attach-group-policy \
    --group-name junior-dev \
    --policy-arn arn:aws:iam::000000000000:policy/Junior-dev-policy

# -------------------------------------------------------------
# VPC & Networking - Day 2 (Network Architecture Foundations)
# -------------------------------------------------------------
echo "Building Network Topologies..."

VPC_ID=$(awslocal ec2 create-vpc \
    --cidr-block 10.0.0.0/16 \
    --query 'Vpc.VpcId' \
    --output text)
echo "VPC Created: $VPC_ID"

PUBLIC_SUBNET=$(awslocal ec2 create-subnet \
    --vpc-id $VPC_ID \
    --cidr-block 10.0.1.0/24 \
    --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=public-subnet}]' \
    --query 'Subnet.SubnetId' \
    --output text)
echo "Public Subnet (DMZ): $PUBLIC_SUBNET"

PRIVATE_SUBNET=$(awslocal ec2 create-subnet \
    --vpc-id $VPC_ID \
    --cidr-block 10.0.2.0/24 \
    --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=private-subnet}]' \
    --query 'Subnet.SubnetId' \
    --output text)
echo "Private Subnet (Internal): $PRIVATE_SUBNET"

IGW_ID=$(awslocal ec2 create-internet-gateway \
    --query 'InternetGateway.InternetGatewayId' \
    --output text)
echo "Internet Gateway: $IGW_ID"

awslocal ec2 attach-internet-gateway --internet-gateway-id $IGW_ID --vpc-id $VPC_ID

RT_ID=$(awslocal ec2 create-route-table \
    --vpc-id $VPC_ID \
    --query 'RouteTable.RouteTableId' \
    --output text)
echo "Route Table: $RT_ID"

# Routing out to the internet highway for the public subnet
awslocal ec2 create-route \
    --route-table-id $RT_ID \
    --destination-cidr-block 0.0.0.0/0 \
    --gateway-id $IGW_ID

awslocal ec2 associate-route-table --route-table-id $RT_ID --subnet-id $PUBLIC_SUBNET

# -------------------------------------------------------------
# Firewalls & Security Groups (DMZ vs. Internal Isolation)
# -------------------------------------------------------------
echo "Configuring Firewalls..."

# DMZ Security Group (Open Ingress to Web/SSH)
DMZ_SG_ID=$(awslocal ec2 create-security-group \
    --group-name web-sg \
    --description "Web server security group for DMZ" \
    --vpc-id $VPC_ID \
    --query 'GroupId' \
    --output text)
echo "DMZ Security Group: $DMZ_SG_ID"

awslocal ec2 authorize-security-group-ingress --group-id $DMZ_SG_ID --protocol tcp --port 80 --cidr 0.0.0.0/0
awslocal ec2 authorize-security-group-ingress --group-id $DMZ_SG_ID --protocol tcp --port 443 --cidr 0.0.0.0/0
awslocal ec2 authorize-security-group-ingress --group-id $DMZ_SG_ID --protocol tcp --port 22 --cidr 0.0.0.0/0

# Internal Backend Security Group (Strict Ingress - Only allows DMZ Group Source)
INTERNAL_SG_ID=$(awslocal ec2 create-security-group \
    --group-name backend-sg \
    --description "Internal server security group" \
    --vpc-id $VPC_ID \
    --query 'GroupId' \
    --output text)
echo "Internal Security Group: $INTERNAL_SG_ID"

awslocal ec2 authorize-security-group-ingress \
    --group-id $INTERNAL_SG_ID \
    --protocol tcp \
    --port 8080 \
    --source-group $DMZ_SG_ID

# -------------------------------------------------------------
# Compute & Storage Deployment (The Actual Assets)
# -------------------------------------------------------------
echo "Deploying Storage Buckets and Files..."

# Setup S3 Buckets
awslocal s3api create-bucket --bucket raj-local-storage
awslocal s3api create-bucket --bucket raj-secure-vault

echo "Base Cloud Data" > /tmp/test-file.txt
echo "Alice is allowed to see this secret." > /tmp/public-data.txt
echo "This is highly confidential admin data!" > /tmp/admin-only.txt

awslocal s3 cp /tmp/test-file.txt s3://raj-local-storage/test-file.txt
awslocal s3 cp /tmp/public-data.txt s3://raj-secure-vault/public-data.txt
awslocal s3 cp /tmp/admin-only.txt s3://raj-secure-vault/admin-only.txt

echo "Launching Compute Instances..."

# Launch DMZ Public Server
DMZ_VM_ID=$(awslocal ec2 run-instances \
    --image-id ami-df5de7cc \
    --instance-type t2.micro \
    --key-name my-key \
    --subnet-id $PUBLIC_SUBNET \
    --security-group-ids $DMZ_SG_ID \
    --query 'Instances[0].InstanceId' \
    --output text)
echo "DMZ EC2 Server Launched: $DMZ_VM_ID"

# Launch Internal Backend Private Server
INTERNAL_VM_ID=$(awslocal ec2 run-instances \
    --image-id ami-df5de7cc \
    --instance-type t2.micro \
    --key-name my-key \
    --subnet-id $PRIVATE_SUBNET \
    --security-group-ids $INTERNAL_SG_ID \
    --query 'Instances[0].InstanceId' \
    --output text)
echo "Internal EC2 Server Launched: $INTERNAL_VM_ID"

echo "========================================="
echo "Infrastructure Successfully Initialized!"
echo "========================================="
