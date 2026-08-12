variable "project" {
  description = "Project name"
  type        = string
  default     = "petclinic"
}

variable "environment" {
  description = "Environment name (dev or prod)"
  type        = string

  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "environment must be either \"dev\" or \"prod\"."
  }
}

variable "openai_api_key" {
  description = "OpenAI API key for the GenAI service (empty string skips creating the secret version)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "create_config_server_git_credentials" {
  description = "Create Secrets Manager entries for the Config Server's private Git repo credentials. Leave false when the config repo is public."
  type        = bool
  default     = false
}

variable "config_server_git_username" {
  description = "Git username for the Config Server backing repository (empty string skips creating the secret version)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "config_server_git_password" {
  description = "Git password or personal access token for the Config Server backing repository (empty string skips creating the secret version)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "secret_recovery_window_in_days" {
  description = "Recovery window (in days) before secrets are permanently deleted. 0 allows immediate deletion (convenient for dev destroy/re-apply); use 7-30 for prod to guard against accidental loss."
  type        = number
  default     = 0

  validation {
    condition     = var.secret_recovery_window_in_days == 0 || (var.secret_recovery_window_in_days >= 7 && var.secret_recovery_window_in_days <= 30)
    error_message = "secret_recovery_window_in_days must be 0 (immediate deletion) or between 7 and 30."
  }
}

variable "oidc_provider_arn" {
  description = "EKS OIDC provider ARN, used in the ESO IRSA trust policy"
  type        = string
}

variable "oidc_provider_url" {
  description = "EKS OIDC provider URL without the https:// prefix (e.g. oidc.eks.eu-central-1.amazonaws.com/id/EXAMPLE)"
  type        = string
}

variable "eso_namespace" {
  description = "Kubernetes namespace where the External Secrets Operator runs"
  type        = string
  default     = "external-secrets"
}

variable "eso_service_account" {
  description = "Kubernetes ServiceAccount used by the External Secrets Operator controller"
  type        = string
  default     = "external-secrets-sa"
}

variable "kms_key_arns" {
  description = "Customer-managed KMS key ARNs used to encrypt secrets. Leave empty when using the default aws/secretsmanager key — no kms:Decrypt grant is needed then."
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Additional resource tags"
  type        = map(string)
  default     = {}
}
