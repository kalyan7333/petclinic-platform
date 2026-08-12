# ADR-0008: ArgoCD for GitOps CD

**Status:** Accepted
**Date:** 2026-02-01

**Context:**
CD could be done with `kubectl apply` in GitHub Actions, or with a GitOps tool (ArgoCD, Flux). GitOps pattern: Git is the source of truth, the CD tool reconciles actual state to desired state.

**Decision:**
ArgoCD for continuous delivery. CI builds and pushes images, updates image tags in Git. ArgoCD detects the Git change and deploys.

**Consequences:**
- No `kubectl apply` in CI — CI pipelines only build and push images
- ArgoCD provides drift detection: manual kubectl changes are automatically reverted (selfHeal)
- Dev: auto-sync on every commit. Prod: manual sync requiring explicit approval
- ArgoCD UI gives visibility into deployment state, history, and diff
- Additional component to operate (ArgoCD itself)
- Industry-standard GitOps pattern (Argo CD is CNCF graduated)
