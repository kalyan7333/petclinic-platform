# ADR-0002: EKS Over ECS

**Status:** Accepted
**Date:** 2026-01-15

**Context:**
Both EKS and ECS Fargate can run containerized workloads on AWS. ECS has simpler pricing and no cluster management overhead.

**Decision:**
Use EKS with managed node groups. The application team is Kubernetes-native (Spring Boot, Actuator, Eureka, Zipkin are all K8s-friendly). EKS provides transferable skills across cloud providers.

**Consequences:**
- EKS control plane: $0.10/hour (~$72/month) — fixed cost regardless of workloads
- Requires learning Kubernetes (worth it for the target audience)
- Full K8s ecosystem available: ArgoCD, Karpenter, Prometheus Operator, etc.
- More operational complexity than ECS Fargate
