resource "aws_security_group" "bastion_sg" {
  name        = "${var.name_prefix}-bastion-sg"
  description = "Hardened gateway for SSH and Nginx Web access"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

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

resource "aws_security_group" "private_app_sg" {
  name        = "${var.name_prefix}-private-app-sg"
  description = "Strictly internal firewall rules"
  vpc_id      = var.vpc_id

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

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "bastion" {
  ami                    = var.ami
  instance_type          = var.instance_type
  subnet_id              = var.public_subnet_id
  vpc_security_group_ids = [aws_security_group.bastion_sg.id]

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
    Name = "${var.name_prefix}-bastion-jumpbox"
  }
}

resource "aws_instance" "private_app" {
  ami                    = var.ami
  instance_type          = var.instance_type
  subnet_id              = var.private_subnet_a_id
  vpc_security_group_ids = [aws_security_group.private_app_sg.id]

  tags = {
    Name = "${var.name_prefix}-private-app-host"
  }
}

resource "aws_instance" "web_node_a" {
  ami                    = var.ami
  instance_type          = var.instance_type
  subnet_id              = var.private_subnet_a_id
  vpc_security_group_ids = [aws_security_group.private_app_sg.id]

  user_data = <<-EOF
              #!/bin/bash
              echo "Hello from Node A!" > index.html
              python3 -m http.server 80 &
              EOF

  tags = {
    Name = "${var.name_prefix}-web-node-a"
  }
}

resource "aws_instance" "web_node_b" {
  ami                    = var.ami
  instance_type          = var.instance_type
  subnet_id              = var.private_subnet_b_id
  vpc_security_group_ids = [aws_security_group.private_app_sg.id]

  user_data = <<-EOF
              #!/bin/bash
              echo "Hello from Node B!" > index.html
              python3 -m http.server 80 &
              EOF

  tags = {
    Name = "${var.name_prefix}-web-node-b"
  }
}
