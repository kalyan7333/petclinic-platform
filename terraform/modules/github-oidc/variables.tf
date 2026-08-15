variable "project" {
  description = "Project name"
  type        = string
  default     = "petclinic"
}

variable "environment" {
  description = "Environment name (dev)"
  type        = string
}

# Derived from the application repo remote:
#   git -C ../spring-petclinic-microservices remote get-url origin
#   -> https://github.com/kalyan7333/spring-petclinic-microservices.git
variable "github_owner" {
  description = "GitHub account that owns the application repo fork"
  type        = string
  default     = "kalyan7333"

  validation {
    condition     = can(regex("^[A-Za-z0-9][A-Za-z0-9-]*$", var.github_owner))
    error_message = "github_owner must be a valid GitHub username or org."
  }
}

# Numeric account ID, not the username. GitHub embeds it in the immutable
# subject claim so a recycled username cannot inherit this role's trust.
#   curl -s https://api.github.com/users/kalyan7333 | jq .id
variable "github_owner_id" {
  description = "Numeric GitHub account ID of github_owner (immutable subject claim)"
  type        = string
  default     = "144237510"

  validation {
    condition     = can(regex("^[0-9]+$", var.github_owner_id))
    error_message = "github_owner_id must be the numeric GitHub account ID."
  }
}

variable "app_repository" {
  description = <<-EOT
    Application repo name the CI workflow runs in. The trust policy is scoped to
    this repo (NOT the platform repo) because build-push.yml — the only workflow
    that assumes this role — lives in the application repo fork.
  EOT
  type        = string
  default     = "spring-petclinic-microservices"
}

#   curl -s https://api.github.com/repos/kalyan7333/spring-petclinic-microservices | jq .id
variable "app_repository_id" {
  description = "Numeric GitHub repo ID of app_repository (immutable subject claim)"
  type        = string
  default     = "1331741579"

  validation {
    condition     = can(regex("^[0-9]+$", var.app_repository_id))
    error_message = "app_repository_id must be the numeric GitHub repository ID."
  }
}

variable "allowed_branch" {
  description = "Only workflow runs on this branch of the app repo may assume the role"
  type        = string
  default     = "main"
}

variable "ecr_repository_arns" {
  description = "ARNs of the ECR repositories CI is allowed to push to (least privilege)"
  type        = list(string)

  validation {
    condition     = length(var.ecr_repository_arns) > 0
    error_message = "ecr_repository_arns must contain at least one repository ARN."
  }
}

variable "role_name" {
  description = "Name of the GitHub Actions IAM role (technical-spec.md: CI/CD Pipeline)"
  type        = string
  default     = "petclinic-github-actions-role"
}

variable "create_oidc_provider" {
  description = <<-EOT
    Create the token.actions.githubusercontent.com IAM OIDC provider. Only one
    provider per URL is allowed per AWS account — set false and the module looks
    up the existing one instead (e.g. if another stack already created it).
  EOT
  type        = bool
  default     = true
}

variable "oidc_thumbprints" {
  description = <<-EOT
    Root CA thumbprints for token.actions.githubusercontent.com. AWS no longer
    validates these for the GitHub issuer, but the API still stores them.
  EOT
  type        = list(string)
  default = [
    "6938fd4d98bab03faadb97b34396831e3780aea1",
    "1c58a3a8518e8759bf075b76b750d4f2df264fcd",
  ]
}

variable "tags" {
  description = "Additional resource tags"
  type        = map(string)
  default     = {}
}
