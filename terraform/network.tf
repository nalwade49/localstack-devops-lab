# 1. The Core VPC Sandbox
resource "aws_vpc" "lab_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true

  tags = {
    Name = "raj-dev-vpc"
  }
}

# 2. The Public Subnet (For public-facing nodes)
resource "aws_subnet" "public_subnet" {
  vpc_id                  = aws_vpc.lab_vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true

  tags = {
    Name = "raj-public-subnet"
  }
}

# 3. The Internet Gateway (The exit to the outer world)
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.lab_vpc.id

  tags = {
    Name = "raj-vpc-igw"
  }
}

# 4. Route Table (Directing default traffic through the Gateway)
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.lab_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "raj-public-route-table"
  }
}

# 5. Associating the Subnet to our Route Table rules
resource "aws_route_table_association" "public_assoc" {
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.public_rt.id
}

# 6. The Private Subnet (Completely isolated from the Internet Gateway)
resource "aws_subnet" "private_subnet" {
  vpc_id                  = aws_vpc.lab_vpc.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = false

  tags = {
    Name = "raj-private-subnet"
  }
}

# 7. Public Subnet Network ACL (The Perimeter Guard Gate)
resource "aws_network_acl" "public_nacl" {
  vpc_id     = aws_vpc.lab_vpc.id
  
  # Ensure only ONE subnet_ids argument exists here mapping to both AZs
  subnet_ids = [aws_subnet.public_subnet.id, aws_subnet.public_subnet_b.id]

  # --- INBOUND RULES ---

  # Rule 100: Allow incoming SSH from the world to the Bastion
  ingress {
    protocol   = "tcp"
    rule_no    = 100
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 22
    to_port    = 22
  }

  # Rule 110: Allow inbound return traffic from the internet (Ephemeral Ports)
  ingress {
    protocol   = "tcp"
    rule_no    = 110
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 1024
    to_port    = 65535
  }

  # --- OUTBOUND RULES ---

  # Rule 100: Allow outbound response traffic back to clients (Ephemeral Ports)
  # Crucial because NACL is stateless!
  egress {
    protocol   = "tcp"
    rule_no    = 100
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 1024
    to_port    = 65535
  }

  # Rule 110: Allow outbound connections to the internet for HTTP/HTTPS updates
  egress {
    protocol   = "tcp"
    rule_no    = 110
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 80
    to_port    = 80
  }

  egress {
    protocol   = "tcp"
    rule_no    = 120
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 443
    to_port    = 443
  }

  tags = {
    Name = "raj-public-perimeter-nacl"
  }
}

# 8. Elastic IP for the NAT Gateway
resource "aws_eip" "nat_eip" {
  domain     = "vpc"
  depends_on = [aws_internet_gateway.igw]

  tags = {
    Name = "raj-nat-eip"
  }
}

# 9. The NAT Gateway (Must be deployed inside the Public Subnet)
resource "aws_nat_gateway" "nat_gw" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.public_subnet.id

  tags = {
    Name = "raj-nat-gateway"
  }
}

# 10. Private Route Table (Directing outbound traffic through the NAT)
resource "aws_route_table" "private_rt" {
  vpc_id = aws_vpc.lab_vpc.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat_gw.id
  }

  tags = {
    Name = "raj-private-route-table"
  }
}

# 11. Associating the Private Subnet to our new Private Route Table rules
resource "aws_route_table_association" "private_assoc" {
  subnet_id      = aws_subnet.private_subnet.id
  route_table_id = aws_route_table.private_rt.id
}

# 12. Second Public Subnet (AZ: us-east-1b)
resource "aws_subnet" "public_subnet_b" {
  vpc_id                  = aws_vpc.lab_vpc.id
  cidr_block              = "10.0.3.0/24"
  availability_zone       = "us-east-1b"
  map_public_ip_on_launch = true

  tags = {
    Name = "raj-public-subnet-b"
  }
}

resource "aws_route_table_association" "public_assoc_b" {
  subnet_id      = aws_subnet.public_subnet_b.id
  route_table_id = aws_route_table.public_rt.id
}

# 13. Second Private Subnet (AZ: us-east-1b)
resource "aws_subnet" "private_subnet_b" {
  vpc_id                  = aws_vpc.lab_vpc.id
  cidr_block              = "10.0.4.0/24"
  availability_zone       = "us-east-1b"
  map_public_ip_on_launch = false

  tags = {
    Name = "raj-private-subnet-b"
  }
}

resource "aws_route_table_association" "private_assoc_b" {
  subnet_id      = aws_subnet.private_subnet_b.id
  route_table_id = aws_route_table.private_rt.id
}
