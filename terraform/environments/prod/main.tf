locals {
  env     = var.environment
  project = var.project
  region  = var.aws_region
}

# E-2: VPC — PETPLAT-10
module "vpc" {
  source = "../../modules/vpc"

  project     = local.project
  environment = local.env

  vpc_cidr            = "10.1.0.0/16"
  public_subnet_cidrs = ["10.1.1.0/24", "10.1.2.0/24"]
  availability_zones  = ["eu-central-1a", "eu-central-1b"]
}

# E-3: EKS — PETPLAT-17
module "eks" {
  source = "../../modules/eks"

  project     = local.project
  environment = local.env

  subnet_ids    = module.vpc.public_subnet_ids
  cluster_sg_id = module.vpc.eks_cluster_sg_id
  node_sg_id    = module.vpc.eks_node_sg_id

  node_instance_types = ["t4g.small"]
  node_ami_type       = "AL2_ARM_64"
  node_min_size       = 2
  node_max_size       = 4
  node_desired_size   = 2
  node_disk_size      = 20
}

# E-4: ECR — PETPLAT-20 (prod: IMMUTABLE tags)
module "ecr" {
  source = "../../modules/ecr"

  project     = local.project
  environment = local.env

  service_names = [
    "config-server",
    "discovery-server",
    "api-gateway",
    "customers-service",
    "visits-service",
    "vets-service",
    "genai-service",
    "admin-server",
  ]

  image_tag_mutability = "IMMUTABLE"
}

# E-5: RDS — PETPLAT-27
module "rds" {
  source = "../../modules/rds"

  project     = local.project
  environment = local.env

  subnet_ids        = module.vpc.public_subnet_ids
  security_group_id = module.vpc.rds_sg_id

  instance_class          = "db.t4g.micro"
  allocated_storage       = 20
  max_allocated_storage   = 20
  multi_az                = false
  backup_retention_period = 7
  skip_final_snapshot     = true
  deletion_protection     = false
}

# E-6: DNS — set domain_name in terraform.tfvars
module "dns" {
  source = "../../modules/dns"

  domain_name = var.domain_name

  count = var.domain_name != "" ? 1 : 0
}

# E-7: Secrets — PETPLAT-33
module "secrets" {
  source = "../../modules/secrets"

  project        = local.project
  environment    = local.env
  openai_api_key = var.openai_api_key
}
