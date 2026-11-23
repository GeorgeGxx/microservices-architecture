aws_region           = "us-east-1"
project_name         = "microservices"
environment          = "dev"
instance_type        = "t3.xlarge" # 4 vCPU, 16 GB RAM (ideal for development & compact integration)
root_volume_size     = 50
key_pair_name        = "microservices-dev-key"
ssh_private_key_path = "~/.ssh/id_rsa"
admin_cidr           = "203.0.113.10/32" # Replace with your operator IP/CIDR (e.g. 198.51.100.5/32)
