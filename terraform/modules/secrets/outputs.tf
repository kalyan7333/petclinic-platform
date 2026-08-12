output "openai_secret_arn" {
  description = "Secrets Manager ARN for the OpenAI API key"
  value       = aws_secretsmanager_secret.openai.arn
}

output "openai_secret_name" {
  description = "Secrets Manager secret name for the OpenAI API key (used in the ExternalSecret remoteRef.key)"
  value       = aws_secretsmanager_secret.openai.name
}

output "config_server_git_username_secret_arn" {
  description = "Secrets Manager ARN for the Config Server Git username (empty when not created)"
  value       = try(aws_secretsmanager_secret.config_server_git_username[0].arn, "")
}

output "config_server_git_password_secret_arn" {
  description = "Secrets Manager ARN for the Config Server Git password (empty when not created)"
  value       = try(aws_secretsmanager_secret.config_server_git_password[0].arn, "")
}

output "eso_role_arn" {
  description = "IRSA role ARN for the External Secrets Operator ServiceAccount annotation"
  value       = aws_iam_role.eso.arn
}

output "eso_role_name" {
  description = "IRSA role name for the External Secrets Operator"
  value       = aws_iam_role.eso.name
}
