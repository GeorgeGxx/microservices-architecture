module "vpc" {
  source = "../../modules/aws/vpc"

  name                 = local.name
  environment          = local.env
  vpc_cidr             = local.cfg.vpc_cidr
  azs                  = var.azs
  public_subnet_cidrs  = local.cfg.public_subnet_cidrs
  private_subnet_cidrs = local.cfg.private_subnet_cidrs
  single_nat_gateway   = local.cfg.single_nat_gateway
  tags                 = local.tags
}

module "eks" {
  source = "../../modules/aws/eks"

  name                = local.name
  environment         = local.env
  vpc_id              = module.vpc.vpc_id
  private_subnet_ids  = module.vpc.private_subnet_ids
  public_subnet_ids   = module.vpc.public_subnet_ids
  node_instance_types = local.cfg.node_instance_types
  node_capacity_type  = local.cfg.node_capacity_type
  node_desired_size   = local.cfg.node_desired_size
  node_min_size       = local.cfg.node_min_size
  node_max_size       = local.cfg.node_max_size
  tags                = local.tags
}

module "ecr" {
  source      = "../../modules/aws/ecr"
  environment = local.env
  tags        = local.tags
}

module "rds_postgres" {
  count  = local.cfg.enable_managed_rds ? 1 : 0
  source = "../../modules/aws/rds"

  name                       = "${local.name}-postgres"
  environment                = local.env
  db_name                    = "microservices_db"
  master_password            = var.db_master_password
  vpc_id                     = module.vpc.vpc_id
  private_subnet_ids         = module.vpc.private_subnet_ids
  allowed_security_group_ids = [module.eks.node_security_group_id]
  instance_class             = local.cfg.db_instance_class
  multi_az                   = local.cfg.db_multi_az
  deletion_protection        = local.cfg.deletion_protection
  tags                       = local.tags
}

module "alb" {
  source = "../../modules/aws/alb"

  name              = local.name
  environment       = local.env
  vpc_id            = module.vpc.vpc_id
  public_subnet_ids = module.vpc.public_subnet_ids
  tags              = local.tags
}

module "irsa_lb_controller" {
  source = "../../modules/aws/iam-irsa"

  name                 = local.name
  oidc_provider_arn    = module.eks.oidc_provider_arn
  oidc_issuer_url      = module.eks.oidc_issuer_url
  namespace            = "kube-system"
  service_account_name = "aws-load-balancer-controller"
  policy_arns          = ["arn:aws:iam::aws:policy/ElasticLoadBalancingFullAccess"]
  tags                 = local.tags
}

module "github_actions_oidc" {
  source = "../../modules/aws/oidc_github"

  environment          = local.env
  github_repo          = "georgegxx/microservices-architecture"
  create_oidc_provider = true
  tags                 = local.tags
}
