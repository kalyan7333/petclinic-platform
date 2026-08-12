output "role_arn" {
  description = "ARN of the GitHub Actions IAM role — set as the AWS_ROLE_ARN secret in the app repo"
  value       = aws_iam_role.github_actions.arn
}

output "role_name" {
  description = "Name of the GitHub Actions IAM role"
  value       = aws_iam_role.github_actions.name
}

output "oidc_provider_arn" {
  description = "ARN of the token.actions.githubusercontent.com IAM OIDC provider"
  value       = local.oidc_provider_arn
}

output "allowed_subject" {
  description = "The single token.actions.githubusercontent.com:sub value permitted to assume the role"
  value       = local.allowed_subject
}
