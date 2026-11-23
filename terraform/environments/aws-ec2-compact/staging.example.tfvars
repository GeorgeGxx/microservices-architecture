aws_region           = "us-east-1"
project_name         = "microservices"
environment          = "staging"
instance_type        = "t3.2xlarge" # 8 vCPU, 32 GB RAM (pre-production sizing for load testing & staging)
root_volume_size     = 80
key_pair_name        = "microservices-staging-key"
ssh_private_key_path = "~/.ssh/id_rsa"
admin_cidr           = "203.0.113.10/32" # Replace with your operator IP/CIDR (e.g. 198.51.100.5/32)
