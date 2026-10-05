terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.40"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.4"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# ==============================================================================
# LIGHTWEIGHT VPC (SINGLE PUBLIC SUBNET)
# ==============================================================================
resource "aws_vpc" "compact_vpc" {
  cidr_block           = "10.20.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name        = "${var.project_name}-compact-vpc"
    Environment = var.environment
  }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.compact_vpc.id
  cidr_block              = "10.20.1.0/24"
  map_public_ip_on_launch = false

  tags = {
    Name = "${var.project_name}-compact-public-subnet"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.compact_vpc.id
  tags   = { Name = "${var.project_name}-compact-igw" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.compact_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = { Name = "${var.project_name}-compact-rt" }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# ==============================================================================
# SECURITY GROUP (HTTP, HTTPS, SSH)
# ==============================================================================
# trivy:ignore:AVD-AWS-0104 Egress required for package updates and container registry access
resource "aws_security_group" "compact_host" {
  name        = "${var.project_name}-compact-host-sg"
  description = "Inbound HTTP, HTTPS, and SSH access"
  vpc_id      = aws_vpc.compact_vpc.id

  ingress {
    description = "SSH administrative access"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.admin_cidr]
  }

  ingress {
    description = "Public HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Public HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Direct Cosmo Router probe (optional)"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = [var.admin_cidr]
  }

  egress {
    description = "Allow outbound HTTPS for container registries and updates"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow outbound HTTP for apt mirrors"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-compact-sg" }
}

# ==============================================================================
# EC2 INSTANCE (UBUNTU 24.04 LTS / 16GB RAM)
# ==============================================================================
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_instance" "compact_host" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type # e.g. t3.xlarge (4 vCPU, 16 GB RAM)
  subnet_id                   = aws_subnet.public.id
  vpc_security_group_ids      = [aws_security_group.compact_host.id]
  key_name                    = var.key_pair_name
  associate_public_ip_address = true

  root_block_device {
    volume_size           = 50
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true
  }

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  tags = {
    Name        = "${var.project_name}-compact-host"
    Environment = var.environment
    ManagedBy   = "terraform-and-ansible"
  }
}

resource "aws_eip" "compact_ip" {
  instance = aws_instance.compact_host.id
  domain   = "vpc"
  tags     = { Name = "${var.project_name}-compact-eip" }
}

# ==============================================================================
# AUTOMATIC ANSIBLE INVENTORY GENERATION
# ==============================================================================
resource "local_file" "ansible_inventory" {
  filename        = "${path.module}/../../../ansible/inventory/hosts.ini"
  file_permission = "0644"
  content         = <<-EOT
[microservices_hosts]
compact-node ansible_host=${aws_eip.compact_ip.public_ip} ansible_user=ubuntu ansible_ssh_private_key_file=${var.ssh_private_key_path}

[microservices_hosts:vars]
ansible_python_interpreter=/usr/bin/python3
environment_tier=${var.environment}
EOT
}
