# ADR-0010: AWS Secrets Manager for Secrets Storage

**Status:** Accepted
**Date:** 2026-01-15

**Context:**
Application secrets (RDS credentials, OpenAI API key) need secure storage. Options: SSM Parameter Store (cheaper, simpler), Secrets Manager (more features), HashiCorp Vault (complex, expensive).

**Decision:**
AWS Secrets Manager with External Secrets Operator (ESO) to sync secrets into Kubernetes. ESO reads from Secrets Manager and creates K8s Secret objects in the namespace.

**Consequences:**
- Secrets Manager cost: $0.40/secret/month + $0.05/10,000 API calls (minimal)
- Secrets never stored in Git or K8s manifests
- Automatic rotation support (native for RDS)
- ESO requires an IRSA role with restricted Secrets Manager read permissions
- More complex than SSM Parameter Store, but is the industry standard pattern
