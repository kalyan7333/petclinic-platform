# Architecture

**Last Updated:** 2026-05-26
**Purpose:** System architecture overview for the Petclinic Platform on AWS.

## Table of Contents
1. [Infrastructure Overview](#infrastructure-overview)
2. [Service Topology](#service-topology)
3. [Network Design](#network-design)
4. [Technology Decisions](#technology-decisions)
5. [Environment Differences](#environment-differences)

---

## Infrastructure Overview

```
Internet
    │
    ▼
[ALB] ── ACM TLS ── Route 53 (petclinic.example.com)
    │
    ▼
[EKS Cluster: petclinic-{env}]
├── kube-system:    CoreDNS, kube-proxy, vpc-cni, EBS CSI, AWS LB Controller, Karpenter
├── argocd:         ArgoCD server, repo-server, application-controller, Redis
├── monitoring:     Prometheus, Grafana, Loki, FluentBit, Alertmanager
├── tracing:        Zipkin
└── petclinic-{env}: 8 microservices
    │
    ▼
[RDS MySQL 8.0: petclinic-{env}] ── petclinic database (shared)
    │
    ▼
[AWS Secrets Manager: petclinic/{env}/rds-credentials, openai-api-key]
    │
[ECR: {account}.dkr.ecr.eu-central-1.amazonaws.com/petclinic-{env}/{service}]
[S3: petclinic-terraform-state + DynamoDB locking]
```

## Service Topology

| Service | Port | Dependencies | DB |
|---------|------|-------------|-----|
| config-server | 8888 | none | no |
| discovery-server | 8761 | config-server | no |
| api-gateway | 8080 | config-server, discovery-server | no |
| customers-service | 8081 | config-server, discovery-server | yes |
| visits-service | 8082 | config-server, discovery-server | yes |
| vets-service | 8083 | config-server, discovery-server | yes |
| genai-service | 8084 | config-server, discovery-server | optional |
| admin-server | 9090 | config-server, discovery-server | no |

**Startup order:** config-server → discovery-server → all others (enforced via init containers)

## Network Design

All-public subnet design (no NAT Gateway — cost optimization, see [ADR-0001](adr/0001-public-subnets.md)):

```
VPC: 10.0.0.0/16 (dev), 10.1.0.0/16 (prod)
├── Public Subnet 1: 10.x.1.0/24 (eu-central-1a)
└── Public Subnet 2: 10.x.2.0/24 (eu-central-1b)

Security Groups (the perimeter):
├── alb-sg:    ingress 80,443 from 0.0.0.0/0
├── eks-cluster-sg: ingress 443 from eks-node-sg
├── eks-node-sg:    ingress all from eks-cluster-sg + self
└── rds-sg:    ingress 3306 from eks-node-sg ONLY
```

## Technology Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Container registry | ECR Private | Production-correct pattern, see [ADR-0009](adr/0009-ecr-private.md) |
| Secrets storage | AWS Secrets Manager | Encrypted, auditable, see [ADR-0010](adr/0010-secrets-manager.md) |
| K8s packaging | Helm (generic chart) | Replaces plain YAML, see [ADR-0007](adr/0007-helm-over-plain-yaml.md) |
| GitOps CD | ArgoCD | See [ADR-0008](adr/0008-argocd-gitops.md) |
| Logging | Loki (in-cluster) | Avoids CloudWatch costs, see [ADR-0011](adr/0011-loki-over-cloudwatch.md) |
| RDS topology | Single shared instance | See [ADR-0003](adr/0003-shared-rds.md) |
| Subnet design | All-public | See [ADR-0001](adr/0001-public-subnets.md) |

## Environment Differences

| Setting | Dev | Prod |
|---------|-----|------|
| K8s namespace | petclinic-dev | petclinic-prod |
| VPC CIDR | 10.0.0.0/16 | 10.1.0.0/16 |
| Service replicas | 1 | 2+ |
| HPA | disabled | enabled |
| PDB | disabled | enabled |
| ArgoCD sync | auto | manual |
| RDS backup retention | 7 days | 30 days |
| RDS final snapshot | skip | keep |
| ECR tag mutability | MUTABLE | IMMUTABLE |
