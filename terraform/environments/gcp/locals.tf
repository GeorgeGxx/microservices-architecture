locals {
  name = "msa-gcp"
  env  = contains(["dev", "staging", "prod"], terraform.workspace) ? terraform.workspace : "dev"

  labels = {
    project             = "microservices-architecture"
    environment         = local.env
    managed_by          = "terraform"
    cloud               = "gcp"
    owner               = "devops-team"
    cost_center         = "engineering-${local.env}"
    security_compliance = "standard"
  }

  env_config = {
    dev = {
      subnet_cidr             = "10.30.0.0/20"
      pods_cidr               = "10.31.0.0/16"
      services_cidr           = "10.32.0.0/20"
      master_cidr             = "172.16.0.0/28"
      enable_gke_autopilot    = true
      enable_managed_database = false
      db_tier                 = "db-custom-2-7680"
      db_high_availability    = false
      db_deletion_protection  = false
      redis_memory_gb         = 1
      redis_high_availability = false
    }
    staging = {
      subnet_cidr             = "10.35.0.0/20"
      pods_cidr               = "10.36.0.0/16"
      services_cidr           = "10.37.0.0/20"
      master_cidr             = "172.16.1.0/28"
      enable_gke_autopilot    = true
      enable_managed_database = true
      db_tier                 = "db-custom-2-7680"
      db_high_availability    = false
      db_deletion_protection  = false
      redis_memory_gb         = 2
      redis_high_availability = false
    }
    prod = {
      subnet_cidr             = "10.40.0.0/20"
      pods_cidr               = "10.41.0.0/16"
      services_cidr           = "10.42.0.0/20"
      master_cidr             = "172.16.2.0/28"
      enable_gke_autopilot    = true
      enable_managed_database = true
      db_tier                 = "db-custom-4-16384"
      db_high_availability    = true
      db_deletion_protection  = true
      redis_memory_gb         = 5
      redis_high_availability = true
    }
  }

  cfg = local.env_config[local.env]
}
