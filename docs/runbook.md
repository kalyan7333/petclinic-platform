# Operations Runbook

**Last Updated:** 2026-05-26
**Purpose:** Day-to-day operational procedures for the Petclinic Platform.

## Table of Contents
1. [Restart a Service](#restart-a-service)
2. [Scale a Service](#scale-a-service)
3. [Rollback a Deployment](#rollback-a-deployment)
4. [Access Logs](#access-logs)
5. [Connect to RDS](#connect-to-rds)
6. [Update EKS Version](#update-eks-version)
7. [Rotate Secrets](#rotate-secrets)
8. [Run Terraform Plan/Apply](#run-terraform-planapply)
9. [Destroy and Recreate the Stack](#destroy-and-recreate-the-stack)

---

### Procedure: Restart a Service

**When:** Service is misbehaving, needs config refresh, or you want a rolling restart.
**Who:** Developer or on-call engineer with kubectl access.
**Time:** 1–2 minutes (rolling restart).

**Steps:**
```bash
kubectl rollout restart deployment/{service-name} -n petclinic-{env}
```

**Verify:**
```bash
kubectl rollout status deployment/{service-name} -n petclinic-{env}
kubectl get pods -n petclinic-{env} -l app.kubernetes.io/name={service-name}
```

**Rollback:**
```bash
kubectl rollout undo deployment/{service-name} -n petclinic-{env}
```

---

### Procedure: Scale a Service

**When:** Traffic increase or decrease warrants manual scaling override.
**Who:** Developer or on-call engineer.
**Time:** 30 seconds.

**Steps (manual override):**
```bash
kubectl scale deployment/{service-name} --replicas=3 -n petclinic-{env}
```

**HPA (prod) — check current state:**
```bash
kubectl get hpa -n petclinic-prod
kubectl describe hpa {service-name}-hpa -n petclinic-prod
```

**Verify:**
```bash
kubectl get pods -n petclinic-{env} -l app.kubernetes.io/name={service-name}
```

---

### Procedure: Rollback a Deployment

> Full detail — method selection, verification, drill procedure, and known traps — is in
> [`docs/rollback-runbook.md`](./rollback-runbook.md) (PETPLAT-54).

**When:** New deployment causes errors or regressions.
**Who:** On-call engineer.
**Time:** 2–5 minutes.

**Option 1 — GitOps rollback (preferred):**
```bash
# In petclinic-platform repo
git log helm-values/{service-name}.yaml          # Find previous tag commit
git revert {commit-sha}
git push origin main
# ArgoCD detects and auto-syncs (dev) or waits for manual sync (prod)
```

**Option 2 — ArgoCD UI rollback:**
1. Open ArgoCD UI: `kubectl port-forward svc/argocd-server -n argocd 8443:443`
2. Find the application, click History and Rollback
3. Select previous sync revision, click Rollback

**Option 3 — kubectl emergency:**
```bash
kubectl rollout undo deployment/{service-name} -n petclinic-{env}
```

**Verify:**
```bash
kubectl rollout status deployment/{service-name} -n petclinic-{env}
```

---

### Procedure: Access Logs

**When:** Investigating errors, tracing requests.
**Who:** Any engineer with kubectl access.
**Time:** Immediate.

**Live pod logs:**
```bash
kubectl logs -f deployment/{service-name} -n petclinic-{env}
kubectl logs -f deployment/{service-name} -n petclinic-{env} --previous  # crashed pod
```

**Grafana/Loki (historical):**
1. `kubectl port-forward svc/grafana -n monitoring 3000:3000`
2. Open http://localhost:3000 → Explore → select Loki datasource
3. Query: `{namespace="petclinic-dev", container="{service-name}"}`

---

### Procedure: Connect to RDS

**When:** Database debugging, schema inspection, query analysis.
**Who:** Senior engineer or DBA.
**Time:** 2–3 minutes.

**Steps:**
```bash
# Get RDS endpoint from Terraform output
cd terraform/environments/{env}
terraform output rds_endpoint

# Start a debug pod with MySQL client
kubectl run -it mysql-debug --image=mysql:8 --rm --restart=Never \
  -n petclinic-{env} \
  --env="MYSQL_PWD=$(kubectl get secret rds-credentials -n petclinic-{env} -o jsonpath='{.data.password}' | base64 -d)" \
  -- mysql -h {RDS_ENDPOINT} -u petclinic -D petclinic
```

**Verify:**
```bash
SHOW TABLES;
```

---

### Procedure: Run Terraform Plan/Apply

**When:** Infrastructure changes needed.
**Who:** Platform engineer with AWS credentials.
**Time:** Plan: 1–2 min. Apply: 5–20 min depending on resources.

**Steps:**
```bash
cd terraform/environments/{env}
terraform init          # Only needed after provider changes
terraform fmt -recursive
terraform validate
terraform plan -out plan.out
# Review plan output carefully — check resource counts and any deletions
terraform apply plan.out
```

**NEVER:**
- `terraform apply` without a saved plan
- `terraform destroy` without approval from team lead

---

### Procedure: Destroy and Recreate the Stack

**When:** DR test, complete environment reset.
**Who:** Platform architect + team lead approval required.
**Time:** Destroy: ~10 min. Recreate: ~30–60 min.

**Steps:**
```bash
# 1. Remove safety hook temporarily (or use --target to destroy specific resources)
cd terraform/environments/{env}
terraform plan -destroy -out destroy.plan
# Have a second engineer review destroy.plan
terraform apply destroy.plan

# 2. Re-bootstrap state (only if S3 bucket was destroyed)
./scripts/bootstrap-state.sh

# 3. Recreate infrastructure
terraform apply plan.out

# 4. Re-deploy services
kubectl apply -f k8s/base/namespaces.yaml
# Or trigger ArgoCD sync after updating kubeconfig
aws eks update-kubeconfig --name petclinic-{env} --region eu-central-1
argocd app sync --all --selector environment={env}

# 5. Verify
./scripts/smoke-test.sh petclinic-{env}
```
