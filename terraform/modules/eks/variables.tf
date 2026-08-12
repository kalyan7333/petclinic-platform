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
    error_message = "Environment must be 'dev' or 'prod'."
  }
}

variable "cluster_version" {
  description = "Kubernetes version (1.29 retired by AWS; pinned to 1.34 for dev and prod)"
  type        = string
  default     = "1.34"
}

variable "public_access_cidrs" {
  description = "CIDR blocks allowed to reach the public API server endpoint. Restrict to office/VPN ranges where possible; defaults to open for the all-public learning design."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "subnet_ids" {
  description = "Subnet IDs for cluster and node group"
  type        = list(string)
}

variable "cluster_sg_id" {
  description = "EKS cluster security group ID"
  type        = string
}

variable "node_sg_id" {
  description = "EKS node security group ID"
  type        = string
}

variable "node_instance_types" {
  description = "Instance types for the managed node group"
  type        = list(string)
  default     = ["t4g.small"]
}

variable "node_ami_type" {
  description = "AMI type for nodes (AL2023_ARM_64_STANDARD for Graviton; AL2 is EOL on K8s 1.33+)"
  type        = string
  default     = "AL2023_ARM_64_STANDARD"
}

variable "node_min_size" {
  description = "Minimum number of nodes"
  type        = number
  default     = 2
}

variable "node_max_size" {
  description = "Maximum number of nodes"
  type        = number
  default     = 4
}

variable "node_desired_size" {
  description = "Desired number of nodes"
  type        = number
  default     = 2
}

variable "node_disk_size" {
  description = "Node disk size in GB"
  type        = number
  default     = 20
}

variable "addon_versions" {
  description = "Pinned EKS managed add-on versions. Defaults target Kubernetes 1.34; update deliberately when bumping cluster_version (see module README)."
  type = object({
    coredns            = string
    kube_proxy         = string
    vpc_cni            = string
    aws_ebs_csi_driver = string
  })
  default = {
    coredns            = "v1.12.4-eksbuild.17"
    kube_proxy         = "v1.34.6-eksbuild.11"
    vpc_cni            = "v1.21.2-eksbuild.2"
    aws_ebs_csi_driver = "v1.62.0-eksbuild.1"
  }
}

variable "tags" {
  description = "Additional resource tags"
  type        = map(string)
  default     = {}
}
