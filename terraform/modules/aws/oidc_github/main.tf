# ==============================================================================
# AWS IAM OpenID Connect (OIDC) Provider & Role for GitHub Actions (Passwordless)
# ==============================================================================

resource "aws_iam_openid_connect_provider" "github_actions" {
  count = var.create_oidc_provider ? 1 : 0

  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1", "1c5876104d8751fa356b092034e44ec7050ea479"]

  tags = merge(var.tags, {
    Name        = "github-actions-oidc-provider"
    Environment = var.environment
    ManagedBy   = "Terraform"
  })
}

data "aws_iam_openid_connect_provider" "existing" {
  count = var.create_oidc_provider ? 0 : 1
  url   = "https://token.actions.githubusercontent.com"
}

locals {
  oidc_provider_arn = var.create_oidc_provider ? aws_iam_openid_connect_provider.github_actions[0].arn : data.aws_iam_openid_connect_provider.existing[0].arn

  repo_variants = distinct([
    var.github_repo,
    lower(var.github_repo)
  ])

  env_branch_map = {
    dev     = ["refs/heads/develop"]
    staging = ["refs/heads/staging"]
    prod    = ["refs/heads/prod"]
  }

  target_branches = lookup(local.env_branch_map, var.environment, ["refs/heads/develop", "refs/heads/staging", "refs/heads/prod"])

  default_allowed_subjects = flatten([
    for repo in local.repo_variants : concat(
      [for ref in local.target_branches : "repo:${repo}:ref:${ref}"],
      ["repo:${repo}:environment:${var.environment}"]
    )
  ])

  effective_allowed_subjects = length(var.allowed_subjects) > 0 ? var.allowed_subjects : local.default_allowed_subjects
}

resource "aws_iam_role" "github_actions_ci_cd" {
  name        = "${var.environment}-github-actions-role"
  description = "IAM Role assumed by GitHub Actions via OIDC for EKS & ECR deployments"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = local.oidc_provider_arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
          StringLike = {
            "token.actions.githubusercontent.com:sub" = local.effective_allowed_subjects
          }
        }
      }
    ]
  })

  tags = merge(var.tags, {
    Name        = "${var.environment}-github-actions-role"
    Environment = var.environment
    ManagedBy   = "Terraform"
  })
}

resource "aws_iam_role_policy_attachment" "ecr_power_user" {
  role       = aws_iam_role.github_actions_ci_cd.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPowerUser"
}

resource "aws_iam_policy" "eks_describe_access" {
  name        = "${var.environment}-github-actions-eks-policy"
  description = "Policy allowing GitHub Actions to describe EKS clusters and update kubeconfig"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "eks:DescribeCluster",
          "eks:ListClusters"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "eks_describe" {
  role       = aws_iam_role.github_actions_ci_cd.name
  policy_arn = aws_iam_policy.eks_describe_access.arn
}
