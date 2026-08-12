# Disaster Recovery Plan

**Last Updated:** 2026-05-26
**Purpose:** Procedures for recovering the Petclinic Platform from failures.

## RTO and RPO Targets

| Resource | RTO | RPO |
|----------|-----|-----|
| EKS cluster + services | 45 minutes | 0 (stateless) |
| RDS database | 60 minutes | 1 hour (automated backups) |
| ECR images | N/A (immutable) | 0 |
| Terraform state | 5 minutes | S3 versioning |

## Backup Strategy

| Data | Backup | Retention | Location |
|------|--------|-----------|---------|
| RDS database | Automated daily snapshots + PITR | 7 days (dev) / 30 days (prod) | RDS |
| Terraform state | S3 versioning enabled | Indefinite | S3: petclinic-terraform-state |
| Container images | ECR lifecycle: keep 10 tagged | 10 latest per service | ECR |
| Git (platform config) | GitHub | Indefinite | GitHub |

## Full Stack Recovery Procedure

**Estimated time: 45–60 minutes**

```bash
# 1. Bootstrap Terraform state (if S3 bucket is gone)
./scripts/bootstrap-state.sh

# 2. Recreate infrastructure (VPC → EKS → RDS → ECR)
cd terraform/environments/{env}
terraform init
terraform apply plan.out   # From last saved plan, or create new plan

# 3. Configure kubectl
aws eks update-kubeconfig --name petclinic-{env} --region eu-central-1

# 4. Install ArgoCD
kubectl create namespace argocd
kubectl apply -k k8s/argocd/install/

# 5. Install External Secrets Operator
kubectl apply -f https://github.com/external-secrets/external-secrets/releases/latest/download/install.yaml

# 6. Apply base K8s manifests
kubectl apply -f k8s/base/namespaces.yaml
kubectl apply -f k8s/base/external-secrets/

# 7. ArgoCD will sync applications once registered
argocd app create --file k8s/argocd/applications/{env}/config-server.yaml
# Repeat for all 8 services or use kubectl apply -f k8s/argocd/applications/{env}/

# 8. Verify
./scripts/smoke-test.sh petclinic-{env}
```

## RDS Point-in-Time Recovery

```bash
# 1. Identify the restore point (must be within retention window)
aws rds describe-db-instances --db-instance-identifier petclinic-{env}

# 2. Restore to point in time (creates new instance)
aws rds restore-db-instance-to-point-in-time \
  --source-db-instance-identifier petclinic-{env} \
  --target-db-instance-identifier petclinic-{env}-restored \
  --restore-time 2026-05-26T10:00:00Z \
  --region eu-central-1

# 3. Update services to use the new endpoint
# Update SPRING_DATASOURCE_URL in helm-values/*-service.yaml
# Trigger ArgoCD sync
```

## Terraform State Recovery

```bash
# List S3 versions for corrupted state
aws s3api list-object-versions \
  --bucket petclinic-terraform-state \
  --prefix petclinic/{env}/terraform.tfstate

# Restore previous version
aws s3api get-object \
  --bucket petclinic-terraform-state \
  --key petclinic/{env}/terraform.tfstate \
  --version-id {VERSION_ID} \
  terraform.tfstate.bak

aws s3 cp terraform.tfstate.bak \
  s3://petclinic-terraform-state/petclinic/{env}/terraform.tfstate
```

## DR Test Schedule

Quarterly test recommended. Next test: see team calendar.

**Test procedure:** Follow [Full Stack Recovery Procedure](#full-stack-recovery-procedure) against dev environment.
Record: time to recover, any manual steps, gaps in documentation.
