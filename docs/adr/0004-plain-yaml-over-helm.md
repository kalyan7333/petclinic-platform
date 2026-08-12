# ADR-0004: Plain Kubernetes YAML (Superseded)

**Status:** Superseded by ADR-0007
**Date:** 2026-01-15

**Context:**
Initial choice was to use plain Kubernetes YAML manifests with Kustomize overlays for environment differences, to keep things simple for learners.

**Decision:**
Plain YAML for base manifests, Kustomize patches for dev/prod differences.

**Consequences:**
- Simple to understand and debug
- Repetitive: each service needs its own copy of similar manifests
- Superseded by Helm (ADR-0007) which provides DRY templating while remaining readable
