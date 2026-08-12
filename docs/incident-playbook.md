# Incident Playbook

**Last Updated:** 2026-05-26
**Purpose:** Diagnosis and resolution steps for common failure scenarios.

## Severity Classification

| Severity | Definition | Response Time | Escalation |
|----------|------------|---------------|-----------|
| SEV1 | Service completely down, all users affected | 15 minutes | L1 → L2 → L3 |
| SEV2 | Degraded service, partial impact | 1 hour | L1 → L2 |
| SEV3 | Minor issue, no user impact | Next business day | L1 |

## Escalation Tiers
- **L1** — On-call engineer
- **L2** — Senior engineer / tech lead
- **L3** — Platform architect / vendor support

---

## Scenario: Pod in CrashLoopBackOff

**Symptoms:** `kubectl get pods` shows `CrashLoopBackOff` status.

**Diagnosis:**
```bash
kubectl describe pod {pod-name} -n petclinic-{env}   # Check Events section
kubectl logs {pod-name} -n petclinic-{env} --previous # Last crash logs
```

**Common causes and resolution:**
1. **OOMKilled** — Increase memory limits in Helm values, redeploy
2. **Config server unreachable** — Verify config-server pod is Running
3. **Missing secret** — Check ExternalSecret sync: `kubectl get externalsecret -n petclinic-{env}`
4. **Bad image** — Rollback to previous image tag (see runbook)

---

## Scenario: Service Not Registering with Eureka

**Symptoms:** API Gateway returns 503, Eureka dashboard missing services.

**Diagnosis:**
```bash
kubectl port-forward svc/discovery-server 8761:8761 -n petclinic-{env}
# Open http://localhost:8761 — which services are registered?
kubectl logs deployment/discovery-server -n petclinic-{env}
kubectl logs deployment/{service-name} -n petclinic-{env} | grep eureka
```

**Resolution:**
1. Verify discovery-server is Running and healthy
2. Verify `CONFIG_SERVER_URL` is correct in service ConfigMap
3. Check network policies allow service → discovery-server:8761
4. Restart the unregistered service: `kubectl rollout restart deployment/{service} -n petclinic-{env}`

---

## Scenario: Database Connection Failures

**Symptoms:** customers/visits/vets service logs show `Unable to acquire JDBC Connection`.

**Diagnosis:**
```bash
kubectl logs deployment/{service-name} -n petclinic-{env} | grep -i "jdbc\|datasource\|connection"
kubectl get secret rds-credentials -n petclinic-{env}   # Verify secret exists
kubectl get externalsecret rds-credentials -n petclinic-{env}   # Check ESO sync
```

**Resolution:**
1. **Secret missing** — Check ESO is running: `kubectl get pods -n external-secrets`
2. **Wrong credentials** — Verify in Secrets Manager: `aws secretsmanager get-secret-value --secret-id petclinic/{env}/rds-credentials`
3. **RDS unreachable** — Check RDS security group allows EKS node SG on 3306
4. **RDS down** — Check RDS console for instance status

---

## Scenario: Image Pull Errors from ECR

**Symptoms:** Pod in `ImagePullBackOff` or `ErrImagePull`.

**Diagnosis:**
```bash
kubectl describe pod {pod-name} -n petclinic-{env}   # Look for "Failed to pull image"
```

**Resolution:**
1. **Tag doesn't exist** — Verify tag in ECR console matches `helm-values/{service}.yaml`
2. **IAM permission** — Verify EKS node role has `AmazonEC2ContainerRegistryReadOnly`
3. **Wrong region** — ECR URI must include eu-central-1
4. **Image never pushed** — Run manual build/push (PETPLAT-85 procedure)

---

## Scenario: Node Not Ready

**Symptoms:** `kubectl get nodes` shows `NotReady`.

**Diagnosis:**
```bash
kubectl describe node {node-name}     # Check Conditions and Events
kubectl get pods -A -o wide | grep {node-name}   # What's running on the node?
```

**Resolution:**
1. **Network plugin issue** — Check vpc-cni pods in kube-system
2. **Disk pressure** — Node is out of disk, terminate and let Karpenter replace
3. **Memory pressure** — Check for OOMKill events, reduce workload
4. **Spot interruption** — Expected; Karpenter provisions replacement automatically

---

## Post-Incident Review Template

```markdown
## Post-Incident Review — {Service} — {Date}

**Severity:** SEV{1|2|3}
**Duration:** {start} → {end} ({total minutes})
**Impact:** {users/services affected}

### Timeline
| Time | Event |
|------|-------|
| HH:MM | Alert fired |
| HH:MM | On-call paged |
| HH:MM | Root cause identified |
| HH:MM | Fix applied |
| HH:MM | Service restored |

### Root Cause
{What actually caused the incident}

### Contributing Factors
{What made it worse or harder to detect}

### Action Items
| Item | Owner | Due |
|------|-------|-----|
| {action} | {name} | {date} |

### Prevention
{How we prevent recurrence}
```
