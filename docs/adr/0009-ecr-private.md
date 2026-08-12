# ADR-0009: ECR Private (Over Docker Hub or ECR Public)

**Status:** Accepted
**Date:** 2026-01-15

**Context:**
Docker Hub has rate limits for unauthenticated pulls. ECR Public is free but requires public images. ECR Private is the production-correct choice for proprietary images.

**Decision:**
ECR Private repositories, one per service per environment. Authenticated via EKS node IAM role (no imagePullSecrets needed).

**Consequences:**
- Cost: ~$0.10/GB storage beyond 500MB free tier — minimal for 8 small Spring Boot images
- EKS nodes authenticate automatically via `AmazonEC2ContainerRegistryReadOnly` IAM policy
- No `imagePullSecrets` in K8s manifests (IAM handles auth)
- ECR scan-on-push provides vulnerability scanning
- Lifecycle policies keep storage costs low (keep 10 tagged, expire untagged after 7 days)
