output "role_arn" {
  description = "ARN of the IAM Role for GitHub Actions OIDC"
  value       = aws_iam_role.github_actions_ci_cd.arn
}

output "role_name" {
  description = "Name of the IAM Role for GitHub Actions OIDC"
  value       = aws_iam_role.github_actions_ci_cd.name
}

output "oidc_provider_arn" {
  description = "ARN of the AWS IAM OIDC Provider for GitHub Actions"
  value       = local.oidc_provider_arn
}
