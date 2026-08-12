# Compliance Checklist

**Last Updated:** 2026-05-26
**Purpose:** Security controls inventory and compliance posture for the Petclinic Platform.

## Encryption at Rest

| Resource | Encryption | Key |
|----------|-----------|-----|
| RDS MySQL | AES-256 (AWS-managed KMS) | aws/rds |
| EBS volumes (EKS nodes) | AES-256 (account default) | aws/ebs |
| S3 Terraform state | SSE-S3 (AES-256) | aws/s3 |
| AWS Secrets Manager | AES-256 | aws/secretsmanager |
| ECR | AES-256 | aws/ecr |

## Encryption in Transit

| Path | Status |
|------|--------|
| Internet → ALB | TLS 1.2+ (ACM certificate) |
| ALB → EKS pods | Plain HTTP (internal VPC, SG-controlled) |
| EKS → RDS | SSL disabled (internal VPC, SG-controlled) |
| EKS → Secrets Manager | TLS (AWS SDK default) |
| EKS → ECR | TLS (AWS SDK default) |

## IAM Roles Inventory

| Role | Principal | Permissions | Scope |
|------|-----------|------------|-------|
| github-actions-petclinic | GitHub OIDC | ECR push, Helm values write | CI/CD only |
| petclinic-{env}-eks-cluster-role | EKS service | AmazonEKSClusterPolicy | Cluster management |
| petclinic-{env}-eks-node-role | EC2 | EKSWorkerNodePolicy, CNI, ECR read | Node operations |
| petclinic-{env}-ebs-csi-role | K8s SA: ebs-csi-controller | AmazonEBSCSIDriverPolicy | PV management |
| petclinic-{env}-karpenter-controller | K8s SA: karpenter | EC2, SQS, IAM (scoped) | Node provisioning |
| petclinic-{env}-eso-role | K8s SA: external-secrets | SecretsManager read (petclinic/* only) | Secret sync |

## RBAC Configuration

| Component | Default | Admin | Developer |
|-----------|---------|-------|-----------|
| ArgoCD | readonly | Full control | View all, sync dev |
| Kubernetes | No cluster-admin for service accounts | Platform team | kubectl read + exec |

## Audit Logging

| Source | Logs where | Retention |
|--------|-----------|-----------|
| AWS CloudTrail | S3 (if enabled) | 90 days |
| EKS control plane audit | CloudWatch Logs (if enabled) | 30 days |
| Application logs | Loki (in-cluster) | 7 days dev / 30 days prod |

## Data Classification

| Data type | Classification | Location | Protection |
|-----------|---------------|---------|-----------|
| PII (owner names, emails) | Confidential | RDS petclinic DB | Encrypted at rest, SG-restricted |
| API keys | Secret | Secrets Manager | Encrypted, ESO sync only |
| DB credentials | Secret | Secrets Manager | Encrypted, ESO sync only |
| Container images | Internal | ECR | Private repo, IAM auth |

## GDPR Considerations
- Data residency: eu-central-1 (Frankfurt) — EU data stays in EU
- Right to erasure: implement at application layer (not in scope for platform)
- Data processor agreement with AWS: covered by AWS DPA

## Vulnerability Scanning

| Tool | Scope | Schedule | Fail threshold |
|------|-------|---------|---------------|
| Checkov | Terraform code | On PR | CRITICAL |
| Trivy | Docker images | Every CI build | CRITICAL (fail), HIGH (warn) |
| ECR scan-on-push | All pushed images | On push | Review manually |

## Remediation SLAs

| Severity | Response time |
|----------|--------------|
| Critical | 24 hours |
| High | 72 hours |
| Medium | 1 week |
| Low | Next sprint |
