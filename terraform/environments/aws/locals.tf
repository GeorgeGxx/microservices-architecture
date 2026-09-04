locals {
  name = "msa-aws"
  env  = contains(["dev", "staging", "prod"], terraform.workspace) ? terraform.workspace : "dev"

  # Corporate Best-Practice Tags for all AWS resources
  tags = {
    Project            = "microservices-architecture"
    Environment        = local.env
    ManagedBy          = "terraform"
    Owner              = "devops-team"
    CostCenter         = "engineering-${local.env}"
    SecurityCompliance = "standard"
    DataClassification = "confidential"
  }

  # Per-workspace sizing: dev (sandbox in data plane) vs prod (dedicated managed infrastructure)
  env_config = {
    dev = {
      vpc_cidr             = "10.10.0.0/16"
      public_subnet_cidrs  = ["10.10.0.0/24", "10.10.1.0/24"]
      private_subnet_cidrs = ["10.10.10.0/24", "10.10.11.0/24"]
      single_nat_gateway   = true
      node_instance_types  = ["t3.medium"]
      node_capacity_type   = "SPOT"
      node_desired_size    = 2
      node_min_size        = 1
      node_max_size        = 3
      enable_managed_rds   = false # in dev/sandbox everything runs in-cluster (data plane)
      db_instance_class    = "db.t3.micro"
      db_multi_az          = false
      deletion_protection  = false
    }
    staging = {
      vpc_cidr             = "10.15.0.0/16"
      public_subnet_cidrs  = ["10.15.0.0/24", "10.15.1.0/24"]
      private_subnet_cidrs = ["10.15.10.0/24", "10.15.11.0/24"]
      single_nat_gateway   = true
      node_instance_types  = ["t3.large"]
      node_capacity_type   = "SPOT"
      node_desired_size    = 2
      node_min_size        = 2
      node_max_size        = 4
      enable_managed_rds   = true # staging uses managed RDS PostgreSQL for true pre-prod testing
      db_instance_class    = "db.t3.small"
      db_multi_az          = false
      deletion_protection  = false
    }
    prod = {
      vpc_cidr             = "10.20.0.0/16"
      public_subnet_cidrs  = ["10.20.0.0/24", "10.20.1.0/24"]
      private_subnet_cidrs = ["10.20.10.0/24", "10.20.11.0/24"]
      single_nat_gateway   = false
      node_instance_types  = ["m6i.large"]
      node_capacity_type   = "ON_DEMAND"
      node_desired_size    = 3
      node_min_size        = 3
      node_max_size        = 6
      enable_managed_rds   = true # in prod provision dedicated AWS RDS PostgreSQL
      db_instance_class    = "db.t3.medium"
      db_multi_az          = true
      deletion_protection  = true
    }
  }

  cfg = local.env_config[local.env]
}
