# 1. The Bastion Firewall (Public Entry Point)
resource "aws_security_group" "bastion_sg" {
  name        = "raj-bastion-sg"
  description = "Hardened gateway for administrative SSH access"
  vpc_id      = aws_vpc.lab_vpc.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] 
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# 2. The Private Subnet Firewall (Security Group Chaining)
resource "aws_security_group" "private_app_sg" {
  name        = "raj-private-app-sg"
  description = "Strictly internal firewall rules"
  vpc_id      = aws_vpc.lab_vpc.id

  ingress {
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    # SECURITY GROUP CHAINING: Only allow access if the traffic originates from the Bastion SG itself!
    security_groups = [aws_security_group.bastion_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# 3. The Bastion Box (Deployed in Public Subnet)
resource "aws_instance" "bastion" {
  ami                    = "ami-df5dbbf0"
  instance_type          = "t2.micro"
  subnet_id              = aws_subnet.public_subnet.id
  vpc_security_group_ids = [aws_security_group.bastion_sg.id]

  tags = {
    Name = "raj-bastion-jumpbox"
  }
}

# 4. The Secure Internal Server (Deployed in Private Subnet)
resource "aws_instance" "private_app" {
  ami                    = "ami-df5dbbf0"
  instance_type          = "t2.micro"
  subnet_id              = aws_subnet.private_subnet.id
  vpc_security_group_ids = [aws_security_group.private_app_sg.id]

  tags = {
    Name = "raj-private-app-host"
  }
}
