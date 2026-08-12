output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "public_subnet_ids" {
  description = "Public subnet IDs"
  value       = module.vpc.public_subnet_ids
}

output "eks_cluster_name" {
  description = "EKS cluster name"
  value       = module.eks.cluster_name
}

output "eks_cluster_endpoint" {
  description = "EKS cluster endpoint"
  value       = module.eks.cluster_endpoint
}

output "eks_oidc_provider_arn" {
  description = "EKS OIDC provider ARN (for IRSA)"
  value       = module.eks.oidc_provider_arn
}

output "ecr_repository_urls" {
  description = "ECR repository URLs keyed by service name"
  value       = module.ecr.repository_urls
}

output "rds_endpoint" {
  description = "RDS instance endpoint"
  value       = module.rds.endpoint
}

output "rds_connection_string" {
  description = "JDBC connection string for SPRING_DATASOURCE_URL"
  value       = module.rds.connection_string
  sensitive   = true
}

output "rds_db_name" {
  description = "RDS database name"
  value       = module.rds.db_name
}

output "rds_secret_arn" {
  description = "Secrets Manager ARN for RDS credentials"
  value       = module.rds.secret_arn
  sensitive   = true
}

output "internet_gateway_id" {
  description = "Internet Gateway ID"
  value       = module.vpc.internet_gateway_id
}

output "kubeconfig_command" {
  description = "Command to update kubeconfig for this cluster"
  value       = "aws eks update-kubeconfig --name ${module.eks.cluster_name} --region ${var.aws_region}"
}

output "lb_controller_role_arn" {
  description = "IAM role ARN for the AWS Load Balancer Controller (pass to install-lb-controller.sh)"
  value       = module.dns.lb_controller_role_arn
}

output "acm_certificate_arn" {
  description = "ACM certificate ARN (set in ingress.yaml annotation; empty when no domain_name is set)"
  value       = module.dns.certificate_arn
}

output "openai_secret_arn" {
  description = "Secrets Manager ARN for the OpenAI API key (petclinic/dev/openai-api-key)"
  value       = module.secrets.openai_secret_arn
}

output "eso_role_arn" {
  description = "IRSA role ARN for the External Secrets Operator (pass to install-external-secrets.sh)"
  value       = module.secrets.eso_role_arn
}

output "install_external_secrets_command" {
  description = "Command to install the External Secrets Operator after Terraform apply"
  value       = "bash scripts/install-external-secrets.sh ${var.environment} ${module.secrets.eso_role_arn}"
}

output "install_lb_controller_command" {
  description = "Command to install the AWS Load Balancer Controller after Terraform apply"
  value       = "bash scripts/install-lb-controller.sh ${module.eks.cluster_name} ${module.dns.lb_controller_role_arn} ${module.vpc.vpc_id}"
}

output "github_actions_role_arn" {
  description = "OIDC role ARN for CI — set as the AWS_ROLE_ARN secret in the application repo (PETPLAT-52)"
  value       = module.github_oidc.role_arn
}

output "github_actions_allowed_subject" {
  description = "The only GitHub OIDC subject permitted to assume the CI role"
  value       = module.github_oidc.allowed_subject
}
