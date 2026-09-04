module "vpc" {
  source = "../../modules/gcp/vpc"

  name          = local.name
  environment   = local.env
  region        = var.region
  subnet_cidr   = local.cfg.subnet_cidr
  pods_cidr     = local.cfg.pods_cidr
  services_cidr = local.cfg.services_cidr
}

module "gke" {
  source = "../../modules/gcp/gke"

  name             = local.name
  environment      = local.env
  region           = var.region
  project_id       = var.project_id
  network_name     = module.vpc.network_name
  subnetwork_name  = module.vpc.subnetwork_name
  enable_autopilot = local.cfg.enable_gke_autopilot
  master_cidr      = local.cfg.master_cidr
}

module "gar" {
  source = "../../modules/gcp/gar"

  name        = local.name
  environment = local.env
  region      = var.region
}

module "cloudsql" {
  count  = local.cfg.enable_managed_database ? 1 : 0
  source = "../../modules/gcp/cloudsql"

  name                   = local.name
  environment            = local.env
  region                 = var.region
  network_id             = module.vpc.network_id
  vpc_peering_dependency = module.vpc.private_vpc_connection
  tier                   = local.cfg.db_tier
  high_availability      = local.cfg.db_high_availability
  deletion_protection    = local.cfg.db_deletion_protection
  db_username            = var.db_username
  db_password            = var.db_password
}

module "memorystore" {
  count  = local.cfg.enable_managed_database ? 1 : 0
  source = "../../modules/gcp/memorystore"

  name                   = local.name
  environment            = local.env
  region                 = var.region
  network_id             = module.vpc.network_id
  vpc_peering_dependency = module.vpc.private_vpc_connection
  memory_size_gb         = local.cfg.redis_memory_gb
  high_availability      = local.cfg.redis_high_availability
}
