# Secret Rotation Procedures

**Last Updated:** 2026-07-26
**Purpose:** How to rotate each managed secret safely, install the External Secrets Operator, and add new secrets.

## Secrets Inventory

| Secret | Format | Location | Created by | Rotation frequency | Method |
|--------|--------|----------|------------|-------------------|--------|
| RDS master password | JSON (`username`, `password`) | `petclinic/{env}/rds-credentials` | `terraform/modules/rds/` (PETPLAT-23) | 90 days | Manual or Secrets Manager auto-rotate |
| OpenAI API key | Plaintext | `petclinic/{env}/openai-api-key` | `terraform/modules/secrets/` (PETPLAT-33) | On compromise / 180 days | Manual |
| Config Server Git username | Plaintext | `petclinic/{env}/config-server/git-username` | `terraform/modules/secrets/` (optional, `create_config_server_git_credentials`) | On team change | Manual |
| Config Server Git token | Plaintext | `petclinic/{env}/config-server/git-password` | `terraform/modules/secrets/` (optional, `create_config_server_git_credentials`) | 90 days | Manual |

All secrets are encrypted with the default `aws/secretsmanager` KMS key and read
from the cluster by the External Secrets Operator using the
`petclinic-{env}-eso-role` IRSA role, which is scoped to `petclinic/{env}/*`.

## RDS Password Rotation

**Time:** 5 minutes + ESO sync interval (1h).

```bash
# Generate new password
NEW_PASS=$(openssl rand -base64 24)

# Update in Secrets Manager
aws secretsmanager put-secret-value \
  --secret-id petclinic/{env}/rds-credentials \
  --secret-string "{\"username\":\"petclinic\",\"password\":\"${NEW_PASS}\"}" \
  --region eu-central-1

# Update RDS master password to match
aws rds modify-db-instance \
  --db-instance-identifier petclinic-{env} \
  --master-user-password "${NEW_PASS}" \
  --apply-immediately \
  --region eu-central-1

# Wait for RDS to update (check status)
aws rds describe-db-instances --db-instance-identifier petclinic-{env} \
  --query 'DBInstances[0].DBInstanceStatus' --output text

# Force ESO to re-sync immediately (before the 1h interval)
kubectl annotate externalsecret rds-credentials \
  force-sync=$(date +%s) --overwrite -n petclinic-{env}

# Restart database-backed services to pick up new credentials
for svc in customers-service visits-service vets-service; do
  kubectl rollout restart deployment/$svc -n petclinic-{env}
done
```

**Verify:**
```bash
kubectl logs deployment/customers-service -n petclinic-{env} | grep -i "HikariPool\|datasource"
```

## OpenAI API Key Rotation

**Time:** 2 minutes + ESO sync interval.

```bash
# 1. Generate new key at https://platform.openai.com/api-keys

# 2. Update in Secrets Manager
#    This secret is stored as a plaintext string, NOT JSON — the ExternalSecret
#    reads the whole value (no remoteRef.property).
aws secretsmanager put-secret-value \
  --secret-id petclinic/{env}/openai-api-key \
  --secret-string 'sk-...new-key...' \
  --region eu-central-1

# 3. Force ESO sync
kubectl annotate externalsecret openai-api-key \
  force-sync=$(date +%s) --overwrite -n petclinic-{env}

# 4. Restart GenAI service
kubectl rollout restart deployment/genai-service -n petclinic-{env}
```

**Verify:**
```bash
kubectl logs deployment/genai-service -n petclinic-{env} | grep -i "openai\|api"
```

## ESO Refresh Interval

External Secrets Operator syncs every 1 hour by default.
To change: edit `spec.refreshInterval` in ExternalSecret manifests at `k8s/base/external-secrets/`.

## Installing the External Secrets Operator

**When:** Once per cluster, after `terraform apply` creates the IRSA role (PETPLAT-34).
**Who:** Cluster admin with `kubectl` access and Terraform state read access.
**Time:** ~5 minutes.

**Steps:**
```bash
# 1. Point kubectl at the cluster
aws eks update-kubeconfig --name petclinic-{env} --region eu-central-1

# 2. Install ESO + ClusterSecretStore + ExternalSecrets in one step.
#    The command below is emitted by Terraform with the IRSA role ARN filled in.
bash $(terraform -chdir=terraform/environments/{env} output -raw install_external_secrets_command)
```

What the script does:

| Step | Resource |
|------|----------|
| 1 | ESO CRDs applied with `kubectl apply --server-side` (not owned by Helm) |
| 2 | `external-secrets` namespace + `external-secrets-sa` ServiceAccount annotated with the IRSA role |
| 3 | ESO controller via Helm, `serviceAccount.create=false`, `installCRDs=false` |
| 4 | `ClusterSecretStore/aws-secrets-manager` (provider `aws`, service `SecretsManager`) |
| 5 | `ExternalSecret/rds-credentials` and `ExternalSecret/openai-api-key` in `petclinic-{env}` |
| 6 | Waits for both ExternalSecrets to report `Ready` and lists the resulting K8s Secrets |

**Verify:**
```bash
kubectl get pods -n external-secrets
kubectl get clustersecretstore aws-secrets-manager
kubectl get externalsecret -n petclinic-{env}
kubectl get secret rds-credentials openai-api-key -n petclinic-{env}
```

**Rollback:**
```bash
helm uninstall external-secrets -n external-secrets
# CRDs and synced Secrets survive (deletionPolicy: Retain), so running pods keep
# their credentials. Remove CRDs only when decommissioning the cluster.
```

## Adding a New Secret

**When:** A service needs a new credential or API key.
**Who:** Platform engineer with Terraform apply rights.
**Time:** ~10 minutes + ESO sync.

**Steps:**

1. **Create the secret in Terraform** — add to `terraform/modules/secrets/main.tf`:

```hcl
resource "aws_secretsmanager_secret" "my_new_secret" {
  name                    = "${var.project}/${var.environment}/my-new-secret"
  description             = "What this secret is for (${var.environment})"
  recovery_window_in_days = var.secret_recovery_window_in_days
  tags                    = local.tags
}

resource "aws_secretsmanager_secret_version" "my_new_secret" {
  count         = var.my_new_secret != "" ? 1 : 0
  secret_id     = aws_secretsmanager_secret.my_new_secret.id
  secret_string = var.my_new_secret
}
```

   Add a matching `variable "my_new_secret"` with `sensitive = true` and an
   `output` for the ARN. Keep the name under the `petclinic/{env}/` prefix —
   the ESO IAM policy is scoped to that prefix and will not read anything else.

2. **Supply the value** — never commit it. Either pass it at apply time
   (`TF_VAR_my_new_secret=... terraform apply plan.out`) or leave the variable
   empty and write the value out of band:

```bash
aws secretsmanager put-secret-value \
  --secret-id petclinic/{env}/my-new-secret \
  --secret-string 'value' \
  --region eu-central-1
```

3. **Apply Terraform:**

```bash
cd terraform/environments/{env}
terraform plan -out plan.out
terraform apply plan.out
```

4. **Create the ExternalSecret** — `k8s/base/external-secrets/my-new-secret.yaml`.
   Use `ENV_PLACEHOLDER` wherever the environment appears; the install script
   substitutes it:

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: my-new-secret
  namespace: petclinic-ENV_PLACEHOLDER
  labels:
    app.kubernetes.io/name: my-new-secret
    app.kubernetes.io/part-of: petclinic
    app.kubernetes.io/managed-by: kubectl
    app.kubernetes.io/component: infrastructure
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: aws-secrets-manager
    kind: ClusterSecretStore
  target:
    name: my-new-secret
    creationPolicy: Owner
    deletionPolicy: Retain
  data:
    - secretKey: MY_NEW_SECRET       # key inside the K8s Secret
      remoteRef:
        key: petclinic/ENV_PLACEHOLDER/my-new-secret
        # property: fieldName        # only for JSON secrets
```

   Add the manifest name to the `for manifest in ...` loop in
   `scripts/install-external-secrets.sh` so it is applied and verified on install.

5. **Apply it:**

```bash
sed 's|ENV_PLACEHOLDER|{env}|g' k8s/base/external-secrets/my-new-secret.yaml | kubectl apply -f -
```

6. **Consume it from the service** — add to `helm-values/{service}.yaml`:

```yaml
envFromSecret:
  MY_NEW_SECRET:
    secretName: my-new-secret
    key: MY_NEW_SECRET
```

**Verify:**
```bash
kubectl get externalsecret my-new-secret -n petclinic-{env}   # STATUS should be SecretSynced
kubectl get secret my-new-secret -n petclinic-{env}
```

**Rollback:**
```bash
kubectl delete externalsecret my-new-secret -n petclinic-{env}
# The K8s Secret is retained (deletionPolicy: Retain); delete it explicitly if
# the credential must be purged:
kubectl delete secret my-new-secret -n petclinic-{env}
```

## Troubleshooting ESO Sync

| Symptom | Cause | Fix |
|---------|-------|-----|
| `SecretSyncedError: AccessDeniedException` | IRSA trust policy does not match `external-secrets/external-secrets-sa`, or the secret is outside `petclinic/{env}/` | Check `terraform output eso_role_arn`, and the SA annotation: `kubectl get sa external-secrets-sa -n external-secrets -o yaml` |
| `ResourceNotFoundException` | Secret name typo, or Terraform not applied in this environment | `aws secretsmanager list-secrets --region eu-central-1 --query "SecretList[?starts_with(Name,'petclinic/')].Name"` |
| Secret exists but is empty | `aws_secretsmanager_secret_version` was skipped because the tfvar was empty | Write the value with `put-secret-value` (step 2 above) |
| No credentials picked up at all | ESO pod started before the SA annotation existed | `kubectl rollout restart deployment/external-secrets -n external-secrets` |
