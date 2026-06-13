# 1. The Bastion Firewall (Public Entry Point)
resource "aws_security_group" "bastion_sg" {
  name        = "raj-bastion-sg"
  description = "Hardened gateway for SSH and Nginx Web access"
  vpc_id      = aws_vpc.lab_vpc.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # NEW: Open Port 80 for our DIY Load Balancer
  ingress {
    from_port   = 80
    to_port     = 80
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


# 3. The Bastion Box (Now acting as an Nginx Load Balancer)
resource "aws_instance" "bastion" {
  ami                    = "ami-df5dbbf0"
  instance_type          = "t2.micro"
  subnet_id              = aws_subnet.public_subnet.id
  vpc_security_group_ids = [aws_security_group.bastion_sg.id]

  # Dynamically injecting the backend IPs using Terraform syntax
  user_data = <<-EOF
              #!/bin/bash
              apt-get update -y
              apt-get install nginx -y

              cat << 'EOT' > /etc/nginx/nginx.conf
              events {}
              http {
                  upstream backend_nodes {
                      server ${aws_instance.web_node_a.private_ip};
                      server ${aws_instance.web_node_b.private_ip};
                  }
                  server {
                      listen 80;
                      location / {
                          proxy_pass http://backend_nodes;
                      }
                  }
              }
              EOT

              systemctl restart nginx
              EOF

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

# 5. Security Group for the Application Load Balancer
resource "aws_security_group" "alb_sg" {
  name        = "raj-alb-sg"
  description = "Allows public web traffic to the ALB"
  vpc_id      = aws_vpc.lab_vpc.id

  ingress {
    from_port   = 80
    to_port     = 80
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

# 6. Update/Append to Private App Security Group rules
# This ensures web traffic can hit backend nodes ONLY from the ALB
resource "aws_security_group_rule" "allow_alb_to_private" {
  type                     = "ingress"
  from_port                = 80
  to_port                  = 80
  protocol                 = "tcp"
  security_group_id        = aws_security_group.private_app_sg.id
  source_security_group_id = aws_security_group.alb_sg.id
}

# 7. Web Node A (Deployed in Private Subnet A)
resource "aws_instance" "web_node_a" {
  ami                    = "ami-df5dbbf0"
  instance_type          = "t2.micro"
  subnet_id              = aws_subnet.private_subnet.id
  vpc_security_group_ids = [aws_security_group.private_app_sg.id]

  user_data = base64encode(<<-EOF
              #!/bin/bash
              echo "Hello from Node A in us-east-1a!" > index.html
              python3 -m http.server 80 &
              EOF
  )

  tags = {
    Name = "raj-web-node-a"
  }
}

# 8. Web Node B (Deployed in Private Subnet B)
resource "aws_instance" "web_node_b" {
  ami                    = "ami-df5dbbf0"
  instance_type          = "t2.micro"
  subnet_id              = aws_subnet.private_subnet_b.id
  vpc_security_group_ids = [aws_security_group.private_app_sg.id]

  user_data = base64encode(<<-EOF
              #!/bin/bash
              echo "Hello from Node B in us-east-1b!" > index.html
              python3 -m http.server 80 &
              EOF
  )

  tags = {
    Name = "raj-web-node-b"
  }
}
