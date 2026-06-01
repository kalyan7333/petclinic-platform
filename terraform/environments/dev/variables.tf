variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "eu-central-1"
}

variable "environment" {
  description = "Environment name (dev or prod)"
  type        = string
  default     = "dev"
}

variable "project" {
  description = "Project name"
  type        = string
  default     = "petclinic"
}

variable "domain_name" {
  description = "Domain name for Route 53 hosted zone and ACM certificate (e.g. example.com)"
  type        = string
  default     = ""
}

variable "openai_api_key" {
  description = "OpenAI API key for the GenAI service"
  type        = string
  sensitive   = true
  default     = ""
}
