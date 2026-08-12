# ADR-0007: Helm Over Plain YAML (Supersedes ADR-0004)

**Status:** Accepted
**Date:** 2026-02-01

**Context:**
ADR-0004 chose plain YAML + Kustomize. After creating manifests for all 8 services, the repetition was significant. A generic Helm chart can template all 8 services from the same templates, with per-service configuration in values files.

**Decision:**
Single generic Helm chart at `helm/petclinic-service/` shared by all 8 services. Per-service config in `helm-values/{service}.yaml`, per-env config in `helm-values/{env}.yaml`.

**Consequences:**
- DRY: one change to templates propagates to all 8 services
- Values files are readable YAML — no complex templating knowledge needed to change ports or replicas
- Works naturally with ArgoCD which has first-class Helm support
- Slightly more initial complexity than plain YAML
- All base K8s YAML manifests remain in `k8s/base/` as reference/fallback
