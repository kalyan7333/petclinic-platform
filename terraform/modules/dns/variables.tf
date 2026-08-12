variable "enable_dns" {
  description = "Create the Route 53 + ACM resources (hosted-zone lookup, wildcard certificate, DNS validation, ALB alias record). Set false when no domain is registered — the LB-controller IAM policy + IRSA role are still created so the ALB works over HTTP."
  type        = bool
  default     = true
}

variable "domain_name" {
  description = "Root domain name for the Route 53 hosted zone (e.g. example.com). Zone must already exist from domain registration. Required only when enable_dns = true; leave empty otherwise."
  type        = string
  default     = ""
}

variable "project" {
  description = "Project name (used for resource naming)"
  type        = string
  default     = "petclinic"
}

variable "environment" {
  description = "Environment name (dev or prod)"
  type        = string
  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "environment must be dev or prod"
  }
}

variable "oidc_provider_arn" {
  description = "EKS OIDC provider ARN (for LB controller IRSA trust policy)"
  type        = string
}

variable "oidc_provider_url" {
  description = "EKS OIDC provider URL without https:// prefix (for IRSA condition keys)"
  type        = string
}

variable "subdomain" {
  description = "Subdomain prefix for the Route 53 alias record (e.g. petclinic-dev creates petclinic-dev.example.com)"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID where the ALB will be created (used to scope LB controller IAM policy to this VPC)"
  type        = string
}

variable "alb_dns_name" {
  description = "ALB DNS hostname from the K8s Ingress status. Leave empty on first apply. Set after the LB controller provisions the ALB and re-apply to create the Route 53 alias record."
  type        = string
  default     = ""
}

variable "tags" {
  description = "Additional resource tags"
  type        = map(string)
  default     = {}
}
