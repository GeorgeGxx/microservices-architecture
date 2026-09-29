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
    CostAllocation     = "opencost-workload-allocation"
    SecurityCompliance = "standard"
    DataClassification = "confidential"
  }

  # Per-workspace sizing: dev (sandbox in data plane) vs prod (dedicated managed infrastructure)
  env_config = {
    dev = {
      vpc_cidr                 = "10.10.0.0/16"
      public_subnet_cidrs      = ["10.10.0.0/24", "10.10.1.0/24"]
      private_subnet_cidrs     = ["10.10.10.0/24", "10.10.11.0/24"]
      single_nat_gateway       = true
      node_instance_types      = ["t3.medium"]
      node_capacity_type       = "SPOT"
      node_desired_size        = 2
      node_min_size            = 1
      node_max_size            = 3
      enable_managed_rds       = false # in dev everything runs in-cluster (data plane)
      db_instance_class        = "db.t3.micro"
      db_multi_az              = false
      deletion_protection      = false
      enable_kms               = true
      enable_elasticache       = false
      elasticache_node_type    = "cache.t4g.micro"
      elasticache_num_clusters = 1
      elasticache_multi_az     = false
      enable_msk               = false
      msk_instance_type        = "kafka.t3.small"
      msk_broker_nodes         = 2
      enable_s3_assets         = true
      enable_cloudfront        = false
      enable_route53_acm       = false
      domain_name              = "dev.msa.local"
      log_retention_days       = 7
    }
    staging = {
      vpc_cidr                 = "10.15.0.0/16"
      public_subnet_cidrs      = ["10.15.0.0/24", "10.15.1.0/24"]
      private_subnet_cidrs     = ["10.15.10.0/24", "10.15.11.0/24"]
      single_nat_gateway       = true
      node_instance_types      = ["t3.large"]
      node_capacity_type       = "SPOT"
      node_desired_size        = 2
      node_min_size            = 2
      node_max_size            = 4
      enable_managed_rds       = true # staging uses managed RDS PostgreSQL
      db_instance_class        = "db.t3.small"
      db_multi_az              = false
      deletion_protection      = false
      enable_kms               = true
      enable_elasticache       = true
      elasticache_node_type    = "cache.t4g.small"
      elasticache_num_clusters = 2
      elasticache_multi_az     = true
      enable_msk               = true
      msk_instance_type        = "kafka.t3.small"
      msk_broker_nodes         = 2
      enable_s3_assets         = true
      enable_cloudfront        = true
      enable_route53_acm       = true
      domain_name              = "staging.msa.example.com"
      log_retention_days       = 30
    }
    prod = {
      vpc_cidr                 = "10.20.0.0/16"
      public_subnet_cidrs      = ["10.20.0.0/24", "10.20.1.0/24"]
      private_subnet_cidrs     = ["10.20.10.0/24", "10.20.11.0/24"]
      single_nat_gateway       = false
      node_instance_types      = ["m6i.large"]
      node_capacity_type       = "ON_DEMAND"
      node_desired_size        = 3
      node_min_size            = 3
      node_max_size            = 6
      enable_managed_rds       = true # in prod provision dedicated AWS RDS PostgreSQL
      db_instance_class        = "db.t3.medium"
      db_multi_az              = true
      deletion_protection      = true
      enable_kms               = true
      enable_elasticache       = true
      elasticache_node_type    = "cache.m6g.large"
      elasticache_num_clusters = 3
      elasticache_multi_az     = true
      enable_msk               = true
      msk_instance_type        = "kafka.m5.large"
      msk_broker_nodes         = 3
      enable_s3_assets         = true
      enable_cloudfront        = true
      enable_route53_acm       = true
      domain_name              = "msa.example.com"
      log_retention_days       = 90
    }
  }

  cfg = local.env_config[local.env]
}

locals {
  microservices_chart            = yamldecode(file("${path.module}/../../../helm/microservices-umbrella/Chart.yaml"))
  microservices_chart_repository = local.microservices_chart.annotations["microservices-architecture.io/helm-oci-repository"]
}
