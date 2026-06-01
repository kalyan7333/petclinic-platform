variable "project" {
  description = "Project name"
  type        = string
  default     = "petclinic"
}

variable "environment" {
  description = "Environment name (dev or prod)"
  type        = string
}

variable "service_names" {
  description = "List of service names - one ECR repo created per service"
  type        = list(string)

  validation {
    condition     = length(var.service_names) > 0
    error_message = "service_names must contain at least one service."
  }
}

variable "image_tag_mutability" {
  description = "Tag mutability: MUTABLE (dev) or IMMUTABLE (prod)"
  type        = string
  default     = "MUTABLE"

  validation {
    condition     = contains(["MUTABLE", "IMMUTABLE"], var.image_tag_mutability)
    error_message = "Must be MUTABLE or IMMUTABLE."
  }
}

variable "max_image_count" {
  description = "Maximum number of images to retain per repository (lifecycle policy)"
  type        = number
  default     = 10

  validation {
    condition     = var.max_image_count > 0
    error_message = "max_image_count must be a positive integer."
  }
}

variable "tags" {
  description = "Additional resource tags"
  type        = map(string)
  default     = {}
}
