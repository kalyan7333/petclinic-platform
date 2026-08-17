locals {
  env     = var.environment
  project = var.project
  region  = var.aws_region
}

# E-2: VPC — PETPLAT-9
module "vpc" {
  source = "../../modules/vpc"

  project     = local.project
  environment = local.env

  vpc_cidr            = "10.0.0.0/16"
  public_subnet_cidrs = ["10.0.1.0/24", "10.0.2.0/24"]
  availability_zones  = ["eu-central-1a", "eu-central-1b"]
}

# E-3: EKS — PETPLAT-15
module "eks" {
  source = "../../modules/eks"

  project     = local.project
  environment = local.env

  subnet_ids    = module.vpc.public_subnet_ids
  cluster_sg_id = module.vpc.eks_cluster_sg_id
  node_sg_id    = module.vpc.eks_node_sg_id

  # t4g.small is the largest Graviton type the FREE account plan allows to
  # launch; t4g.medium fails with AsgInstanceLaunchFailures / "not eligible for
  # Free Tier". Raise this once the account is off the free-tier plan.
  node_instance_types = ["t4g.small"]
  node_ami_type       = "AL2023_ARM_64_STANDARD"
  node_min_size       = 2
  node_max_size       = 4
  # 4 nodes, not 2: t4g.small caps out at 11 pods per node (3 ENIs x 4 IPs - 1),
  # and the cluster add-ons (ArgoCD 7, ESO 3, LB controller 2, coredns 2, plus
  # 2 DaemonSet pods per node) fill all 22 slots on a 2-node cluster, leaving
  # none for the 8 services. This is an ENI/IP limit, not CPU or memory — both
  # sit under 30% utilised. Raise node count rather than instance size: t4g.small
  # is the free-tier ceiling and arm64 is required by every image.
  node_desired_size = 4
  node_disk_size    = 20
}

# E-4: ECR — PETPLAT-20
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

  image_tag_mutability = "MUTABLE"
}

# E-5: RDS — PETPLAT-25
module "rds" {
  source = "../../modules/rds"

  project     = local.project
  environment = local.env

  subnet_ids        = module.vpc.public_subnet_ids
  security_group_id = module.vpc.rds_sg_id

  instance_class        = "db.t4g.micro"
  allocated_storage     = 20
  max_allocated_storage = 20
  multi_az              = false
  # PETPLAT-25 AC calls for 7-day retention, but this AWS account is on the
  # restricted Free Tier plan which rejects retention > 0 with a
  # FreeTierRestrictionError. Kept at 0 (automated backups disabled) so the
  # instance can be created. Raise to 7 once the account is off the free-tier plan.
  backup_retention_period = 0
  skip_final_snapshot     = true
  deletion_protection     = false
}

# E-6: DNS & Ingress — PETPLAT-28/29/31/32
# Set domain_name in terraform.tfvars. Leave alb_dns_name empty on first apply.
# After kubectl apply creates the ingress and the ALB is provisioned, set alb_dns_name
# from `kubectl get ingress -n petclinic-dev petclinic-ingress -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'`
# and re-apply to create the Route 53 alias record.
module "dns" {
  source = "../../modules/dns"

  # DNS (Route 53 + ACM) turns on only when a domain is provided. With no domain
  # the module still creates the LB-controller IRSA role so the ALB works over HTTP.
  enable_dns  = var.domain_name != ""
  domain_name = var.domain_name
  project     = local.project
  environment = local.env
  subdomain   = "petclinic-${local.env}"

  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_provider_url = module.eks.oidc_provider_url

  vpc_id       = module.vpc.vpc_id
  alb_dns_name = var.alb_dns_name
}

# E-7: Secrets — PETPLAT-33/37
# Non-RDS application secrets plus the IRSA role used by the External Secrets
# Operator. RDS credentials live in the rds module (PETPLAT-23).
module "secrets" {
  source = "../../modules/secrets"

  project        = local.project
  environment    = local.env
  openai_api_key = var.openai_api_key

  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_provider_url = module.eks.oidc_provider_url
}

# E-10: GitHub Actions OIDC federation — PETPLAT-52
# Trust is scoped to the application repo fork (where build-push.yml runs), not
# this platform repo. See terraform/modules/github-oidc/main.tf.
module "github_oidc" {
  source = "../../modules/github-oidc"

  project           = local.project
  environment       = local.env
  github_owner      = "kalyan7333"
  github_owner_id   = "144237510"
  app_repository    = "spring-petclinic-microservices"
  app_repository_id = "1331741579"
  allowed_branch    = "main"

  ecr_repository_arns = values(module.ecr.repository_arns)
}
