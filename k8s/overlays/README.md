# Kubernetes Environment Overlays

**Last Updated:** 2026-08-10

**Purpose:** Kustomize overlays that turn the environment-agnostic manifests in `k8s/base/` into a
deployable dev release. This overlay is also the source of truth for the Helm values in
`helm-values/dev.yaml` (PETPLAT-45 → E-16), which is what ArgoCD actually deploys.

This platform is dev-only — the prod environment (Terraform root module, Kustomize overlay, and the
`deploy-prod` skill) was removed on 2026-08-10.

## Table of Contents

- [Layout](#layout)
- [Dev settings (PETPLAT-45)](#dev-settings-petplat-45)
- [Placeholders to substitute](#placeholders-to-substitute)
- [Rendering and applying](#rendering-and-applying)
- [Mapping to Helm values](#mapping-to-helm-values)

## Layout

```
k8s/base/
├── kustomization.yaml          # aggregates the 8 services + ingress
├── namespaces.yaml             # applied directly, NOT via an overlay (see below)
└── {service}/kustomization.yaml
k8s/overlays/
└── dev/   kustomization.yaml, replica-patch.yaml, datasource-patch.yaml
```

`k8s/base/namespaces.yaml` is **not** a resource of the overlay. Kustomize's namespace transformer
rewrites the name of every `Namespace` object it renders, so the namespace is applied once, directly:

```bash
kubectl apply -f k8s/base/namespaces.yaml
```

`k8s/base/external-secrets/` is likewise excluded — its manifests carry `ENV_PLACEHOLDER`
namespaces that `scripts/install-external-secrets.sh` substitutes at install time, and the
`ExternalSecret` CRD does not exist until the operator is installed.

## Dev settings (PETPLAT-45)

| Parameter | Value |
|-----------|-------|
| Namespace | `petclinic-dev` |
| Replicas (all 8 services) | 1 |
| Resources | Base values — requests `100m`/`128Mi`, limits `500m`/`512Mi` (api-gateway `200m`/`1000m` CPU) |
| HPA | Disabled |
| PDB | Disabled |
| Image repo | `{account}.dkr.ecr.eu-central-1.amazonaws.com/petclinic-dev/{service}` |
| Image tag | 7-character commit SHA from CI; the initial deploy uses the tag pushed in PETPLAT-85 |
| Datasource | Dev RDS endpoint patched into the three DB service ConfigMaps |

The base manifests are already sized for dev, so the dev overlay adds no resource patch — it only
pins replicas, namespace and images.

## Placeholders to substitute

| Placeholder | Where | Replace with |
|-------------|-------|--------------|
| `REPLACE_WITH_ECR_URI` | overlay `images[]` | `terraform -chdir=terraform/environments/dev output -raw ecr_registry_url` |
| `REPLACE_WITH_IMAGE_TAG` | overlay `images[]` | 7-char commit SHA (`${GITHUB_SHA::7}`) |
| `REPLACE_WITH_RDS_ENDPOINT` | `datasource-patch.yaml` | `terraform -chdir=terraform/environments/dev output -raw rds_endpoint` |

## Rendering and applying

```bash
# Render
kubectl kustomize k8s/overlays/dev

# Validate without touching the cluster
kubectl kustomize k8s/overlays/dev | kubectl apply --dry-run=client -f -

# Apply
kubectl apply -f k8s/base/namespaces.yaml
kubectl apply -k k8s/overlays/dev
```

## Mapping to Helm values

| Overlay file | Helm equivalent |
|--------------|-----------------|
| `replica-patch.yaml` | `replicaCount` in `helm-values/dev.yaml` |
| `datasource-patch.yaml` | `env.SPRING_DATASOURCE_URL` in `helm-values/{service}.yaml` |
| `images[]` | `image.repository` / `image.tag` in `helm-values/{service}.yaml` |
