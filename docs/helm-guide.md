# Helm Chart Guide

**Last Updated:** 2026-08-04
**Purpose:** How to use, deploy, and extend the generic Petclinic Helm chart (`helm/petclinic-service/`), which packages all 8 microservices.

## Table of Contents

- [Chart Structure](#chart-structure)
- [Values Merge Order](#values-merge-order)
- [Resource Naming](#resource-naming)
- [Values Reference](#values-reference)
- [Deploy a Service Manually](#deploy-a-service-manually)
- [Validate Before Committing](#validate-before-committing)
- [Add a New Service](#add-a-new-service)
- [Change Resources, Replicas, or Environment Variables](#change-resources-replicas-or-environment-variables)
- [Image Tags and CI](#image-tags-and-ci)
- [Secrets](#secrets)
- [Integration with ArgoCD](#integration-with-argocd)

## Chart Structure

One generic chart serves all 8 services. Per-service differences live entirely in values files.

```
helm/petclinic-service/
├── Chart.yaml          # Chart metadata
├── values.yaml         # Chart defaults (lowest precedence)
└── templates/
    ├── _helpers.tpl    # Names, labels, selectors
    ├── deployment.yaml
    ├── service.yaml
    ├── configmap.yaml  # Rendered only when `env` is non-empty
    ├── serviceaccount.yaml
    ├── hpa.yaml        # Rendered only when hpa.enabled=true
    ├── pdb.yaml        # Rendered only when pdb.enabled=true
    └── NOTES.txt       # Post-install summary

helm-values/
├── {service}.yaml      # Ports, env vars, secrets, init containers
└── dev.yaml            # Dev: registry, namespace, replicas, RDS endpoint
```

**Dev is the only environment deployed today.** The HPA and PDB templates stay in the chart and stay conditional — both default to disabled, so adding an environment later means adding a values file, not editing templates.

The chart reproduces the manifests in `k8s/base/` and the dev patches in `k8s/overlays/dev/`. Those directories remain the reference for what the rendered output must look like; they are no longer the deployment path.

## Values Merge Order

Values merge in this order, later overriding earlier:

1. `helm/petclinic-service/values.yaml` — chart defaults
2. `helm-values/{service}.yaml` — service-specific
3. `helm-values/dev.yaml` — environment-specific

This is plain Helm `-f` precedence — nothing in the templates re-merges values.

Rule of thumb: anything identical across all 8 services in an environment (registry, namespace, replicas, RDS endpoint) goes in the environment file; anything specific to one service (port, Spring profiles, env vars, secrets, init containers) goes in its own file.

## Resource Naming

Every service file pins its rendered names:

```yaml
fullnameOverride: customers-service
```

This is **required**, not cosmetic. Resource names must not follow the Helm release name, because ArgoCD names the release after the Application (`customers-service-dev`). Without the override, the chart would render `Deployment/customers-service-dev` and `Service/customers-service-dev`, and everything that addresses a service by its bare name would break:

- service DNS and `CONFIG_SERVER_URL` / `DISCOVERY_SERVER_URL`
- the init containers polling `http://config-server:8888` and `http://discovery-server:8761`
- the Ingress backend in `k8s/base/ingress/ingress.yaml`
- the `app.kubernetes.io/name` selectors in `k8s/base/security/network-policies.yaml`

`scripts/validate-helm.sh` renders each service a second time under a `{service}-dev` release name and fails if the resource names move, so this cannot regress silently.

The Deployment selector is `app.kubernetes.io/name` only, matching `k8s/base/{service}/deployment.yaml`. Selectors are immutable after creation — do not add labels to `petclinic-service.selectorLabels`.

## Values Reference

| Key | Set in | Purpose |
|-----|--------|---------|
| `fullnameOverride` | service file | Pins rendered resource names — see above |
| `image.registry` | dev.yaml | Registry host **and** ECR project: `…amazonaws.com/petclinic-dev` |
| `image.name` | service file | Image name only (the service name) |
| `image.tag` | service file | Commit SHA — rewritten by CI |
| `component` | service file | `app.kubernetes.io/component`: `server` \| `gateway` \| `service` \| `admin` |
| `containerPort` / `service.port` | service file | 8888, 8761, 8080, 8081, 8082, 8083, 8084, 9090 |
| `springProfiles` | service file | `SPRING_PROFILES_ACTIVE`, e.g. `docker,mysql` |
| `env` | service file | Non-secret config → ConfigMap → `configMapKeyRef` env vars |
| `secrets` | service file | List of `{name, secretName, key}` → `secretKeyRef` env vars |
| `initContainers` | service file | Startup dependency wait containers |
| `probes` | service file | Override only where a service differs (config-server) |
| `resources` | service file | Overridden per service where needed (api-gateway) |
| `rds.endpoint` | dev.yaml | RDS host, interpolated into `SPRING_DATASOURCE_URL` |
| `namespace`, `replicaCount`, `extraLabels` | dev.yaml | `petclinic-dev`, 1 replica, `environment: dev` |
| `hpa`, `pdb` | dev.yaml | Both disabled |

`env` values are rendered through `tpl`, so a per-service value can reference an environment value. That is how the three DB-backed services get the datasource endpoint without duplicating it in each file:

```yaml
# helm-values/customers-service.yaml
env:
  SPRING_DATASOURCE_URL: "jdbc:mysql://{{ .Values.rds.endpoint }}:3306/petclinic?useSSL=false&serverTimezone=UTC&useLegacyDatetimeCode=false"
```

## Deploy a Service Manually

Normal deployments go through ArgoCD. Use these for break-glass or to test a change before committing.

```bash
# Render without deploying (no cluster required)
helm template customers-service helm/petclinic-service/ \
  -f helm-values/customers-service.yaml \
  -f helm-values/dev.yaml

# Deploy customers-service to dev
helm upgrade --install customers-service helm/petclinic-service/ \
  --namespace petclinic-dev \
  -f helm-values/customers-service.yaml \
  -f helm-values/dev.yaml \
  --set image.tag=$(git rev-parse --short HEAD)

# Inspect what is running
helm get manifest customers-service -n petclinic-dev
```

Deploy in startup order: `config-server` → `discovery-server` → the rest. The init containers enforce this, but starting out of order means pods sit in `Init:0/2` until their dependency is healthy.

> Manual `helm upgrade` puts the release out of sync with Git. ArgoCD reverts it on the next sync (dev has self-heal on). Follow up with a Git commit if the change should stick.

## Validate Before Committing

```bash
bash scripts/validate-helm.sh                     # all 8 services
bash scripts/validate-helm.sh --service vets-service
```

The script runs `helm lint` (chart alone and with every service values file), renders all 8 services, and asserts the rendered output against `k8s/base/` and `k8s/overlays/dev/`: namespace, container and service ports, replica count, resource naming under an ArgoCD-style release name, ECR project, probes, security context, resource requests/limits, secret references, and that no HPA or PDB is rendered.

It also runs `kubectl apply --dry-run=client` on each render. That step needs a reachable API server — a client-side dry run still performs API discovery to resolve each kind — so it is reported as **SKIPPED**, never as passed, when no cluster is up:

```bash
bash scripts/start-env.sh dev            # then re-run for full validation
```

## Add a New Service

1. Add the base manifests under `k8s/base/{new-service}/` if the service is new to the platform (they stay the reference for the rendered output).
2. Create `helm-values/{new-service}.yaml`: `fullnameOverride`, `image.name`, `component`, `containerPort`, `service.port`, `springProfiles`, `env`, `secrets`, `initContainers`.
3. Add the service to `SERVICES` and `EXPECTED` in `scripts/validate-helm.sh`, then run it.
4. Add the ECR repository to `terraform/modules/ecr` and the service to the build matrix in `.github/workflows/build-push.yml`.
5. Create the ArgoCD Application: `k8s/argocd/applications/dev/{new-service}.yaml`.
6. Commit. ArgoCD auto-syncs dev.

## Change Resources, Replicas, or Environment Variables

| Change | Where |
|--------|-------|
| Env var for one service | `env:` in `helm-values/{service}.yaml` |
| Env var value that differs per environment | Add the key to `dev.yaml`, reference it with `{{ .Values.<key> }}` in the service file |
| Resources for one service | `resources:` in `helm-values/{service}.yaml` |
| Resources for every service | `resources:` in `helm-values/dev.yaml` (currently unset on purpose — api-gateway needs a larger CPU envelope, and a blanket value here would clobber it) |
| Replica count | `replicaCount` in `helm-values/dev.yaml` |
| Enable an HPA or PDB | `hpa:` / `pdb:` in the values files — both templates are already conditional |

Enabling an HPA requires Metrics Server: `bash scripts/install-metrics-server.sh`. Never add a PDB to a single-replica service — `minAvailable: 1` against one replica blocks node drains entirely.

Run `bash scripts/validate-helm.sh`, then commit. ArgoCD picks up the change.

## Image Tags and CI

Images render as `{image.registry}/{image.name}:{image.tag}`. `image.registry` includes the ECR project and comes from the environment file.

`.github/workflows/update-image-tags.yml` rewrites the tag after a successful build:

```bash
yq -i ".image.tag = \"${SHA}\"" helm-values/${service}.yaml
```

Keep `image.tag` a top-level key in the per-service file or that update breaks. Never set it to `latest` — `scripts/validate-helm.sh` fails if a rendered image ends in `:latest`.

## Secrets

Secrets are never in values files. External Secrets Operator syncs them from AWS Secrets Manager into K8s Secrets (`k8s/base/external-secrets/`), and the chart references them by name and key:

| Secret | Keys | Consumed by |
|--------|------|-------------|
| `rds-credentials` | `username`, `password` | customers-service, visits-service, vets-service |
| `openai-api-key` | `OPENAI_API_KEY` | genai-service |

```yaml
secrets:
  - name: SPRING_DATASOURCE_USERNAME
    secretName: rds-credentials
    key: username
```

Install the operator and the ExternalSecret CRs before the first deploy: `bash scripts/install-external-secrets.sh dev`. Without them the Secrets do not exist and pods stay in `CreateContainerConfigError`.

## Integration with ArgoCD

ArgoCD Application CRDs in `k8s/argocd/applications/dev/{service}.yaml` reference:

- `path: helm/petclinic-service` — the generic chart
- `valueFiles: [../../helm-values/{service}.yaml, ../../helm-values/dev.yaml]` — merged in that order

ArgoCD renders the chart on every sync, so the merge order above is exactly what runs in the cluster. Dev auto-syncs with prune and self-heal. Because the Application is named `{service}-dev`, the Helm release is too — which is exactly why every service file pins `fullnameOverride`. See [ADR-0008](adr/0008-argocd-gitops.md) and [ADR-0007](adr/0007-helm-over-plain-yaml.md).
