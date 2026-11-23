aws_region           = "us-east-1"
project_name         = "microservices"
environment          = "prod"
instance_type        = "c6i.4xlarge" # 16 vCPU, 32 GB RAM (high-performance compute for production throughput)
root_volume_size     = 120
key_pair_name        = "microservices-prod-key"
ssh_private_key_path = "~/.ssh/id_rsa"
admin_cidr           = "203.0.113.10/32" # Replace with your bastion/VPN IP/CIDR (e.g. 198.51.100.5/32)
