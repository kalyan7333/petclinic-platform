# Rollback Runbook

**Last Updated:** 2026-08-11
**Jira:** PETPLAT-54 (rollback strategy), PETPLAT-50 / PETPLAT-87 (image tag mechanism)

**Purpose:** How to roll back a bad deployment in `petclinic-dev`. Deployments are GitOps —
ArgoCD is the only thing that writes to the cluster — so the durable rollback is a Git commit,
not a `kubectl` command.

---

## Table of Contents

1. [How a Deploy Reaches the Cluster](#how-a-deploy-reaches-the-cluster)
2. [Choosing a Rollback Method](#choosing-a-rollback-method)
3. [Procedure: GitOps Rollback (preferred)](#procedure-gitops-rollback-preferred)
4. [Procedure: ArgoCD History Rollback](#procedure-argocd-history-rollback)
5. [Procedure: kubectl Emergency Rollback](#procedure-kubectl-emergency-rollback)
6. [Procedure: Stop the Bleeding — Pause Auto-Sync](#procedure-stop-the-bleeding--pause-auto-sync)
7. [Verification](#verification)
8. [Testing the Rollback Path](#testing-the-rollback-path)
9. [Known Traps](#known-traps)

---

## How a Deploy Reaches the Cluster

```
app repo push to main
  └─ build-push.yml — builds ARM64 images, Trivy scan, push to ECR
       └─ repository_dispatch: app-image-built { sha, services }
            └─ platform repo: .github/workflows/update-image-tags.yml
                 └─ yq writes image.tag in helm-values/{service}.yaml, commits, pushes
                      └─ ArgoCD (auto-sync, prune + self-heal) syncs petclinic-dev
```

The rolled-out image is whatever `image.tag` says in `helm-values/{service}.yaml` on `main`.
**Change that value and you have changed the deployment.** Everything else is a temporary patch
that ArgoCD's `selfHeal` will undo.

| Fact | Value |
|------|-------|
| Namespace | `petclinic-dev` |
| ArgoCD Application name | `{service}-dev` (e.g. `customers-service-dev`) |
| Sync policy | `automated`, `prune: true`, `selfHeal: true` |
| Image registry | `893410593881.dkr.ecr.eu-central-1.amazonaws.com/petclinic-dev` |
| Tag source of truth | `helm-values/{service}.yaml` → `image.tag` |

---

## Choosing a Rollback Method

| Situation | Method | Durable? |
|-----------|--------|----------|
| Bad image deployed, cluster reachable, ArgoCD healthy | [GitOps rollback](#procedure-gitops-rollback-preferred) | Yes |
| Need to undo a whole sync (values + chart changes together) | [ArgoCD history rollback](#procedure-argocd-history-rollback) | No — Git still wins |
| ArgoCD is down or Git is unreachable, service is hard down | [kubectl emergency](#procedure-kubectl-emergency-rollback) | No — `selfHeal` reverts it |
| Repeated bad dispatches keep re-breaking the service | [Pause auto-sync](#procedure-stop-the-bleeding--pause-auto-sync) first, then GitOps rollback | N/A |

Always finish with a GitOps rollback. The other two buy time; only Git changes the desired state.

---

## Procedure: GitOps Rollback (preferred)

**When:** A deployed image is broken and ArgoCD is functioning.
**Who:** On-call engineer with push access to `petclinic-platform`.
**Time:** 2–5 minutes (plus ~1–3 min for pods to roll).

**Steps:**

1. Identify the bad tag and the last known-good tag:
   ```bash
   git -C ~/spring-petclinic/petclinic-platform log --oneline -10 -- helm-values/customers-service.yaml
   git -C ~/spring-petclinic/petclinic-platform log -p -3 -- helm-values/customers-service.yaml | grep -E '^[-+]\s+tag:'
   ```

2. Pick your approach.

   **2a. Revert the tag-update commit** (rolls back every service that commit touched):
   ```bash
   git revert --no-edit <bad-tag-commit-sha>
   ```

   **2b. Set one service back to a specific known-good SHA** (surgical — preferred when only one
   service is broken):
   ```bash
   yq -i '.image.tag = "<known-good-sha>"' helm-values/customers-service.yaml
   git commit -am "fix: roll customers-service back to <known-good-sha> (incident <ticket>)"
   ```

3. Push to `main`:
   ```bash
   git push origin main
   ```

4. Force an immediate sync instead of waiting for the ~3 min poll:
   ```bash
   argocd app sync customers-service-dev
   ```

**Verify:** see [Verification](#verification).

**Rollback (of the rollback):** `git revert` the revert, or set `image.tag` forward again and push.

> **Confirm the tag exists in ECR before pushing** — ECR lifecycle policy keeps only the last 10
> images per repo, so old SHAs age out:
> ```bash
> aws ecr describe-images --region eu-central-1 \
>   --repository-name petclinic-dev/customers-service \
>   --image-ids imageTag=<known-good-sha> \
>   --query 'imageDetails[0].imagePushedAt'
> ```
> If that 404s, the image is gone — rebuild from the good commit in the app repo instead.

---

## Procedure: ArgoCD History Rollback

**When:** You need the whole previous sync back (chart + values), or Git access is slow and you
want the cluster healthy *now*.
**Who:** On-call engineer with ArgoCD access.
**Time:** 1–2 minutes.

**Steps:**

1. Open ArgoCD:
   ```bash
   kubectl port-forward svc/argocd-server -n argocd 8443:443
   ```

2. List sync history and roll back:
   ```bash
   argocd app history customers-service-dev
   argocd app rollback customers-service-dev <history-id>
   ```
   UI equivalent: open the application → **History and Rollback** → select the previous revision →
   **Rollback**.

**Verify:** see [Verification](#verification).

> ArgoCD disables auto-sync on the application when you roll back, so `selfHeal` will not
> immediately re-apply the bad revision. The app now shows `OutOfSync` against `main` — this is
> expected and is your reminder that the fix is not yet in Git. Complete the
> [GitOps rollback](#procedure-gitops-rollback-preferred), then re-enable:
> ```bash
> argocd app set customers-service-dev --sync-policy automated --self-heal --auto-prune
> ```

---

## Procedure: kubectl Emergency Rollback

**When:** Last resort — ArgoCD or GitHub is unavailable and the service is hard down.
**Who:** On-call engineer with cluster access.
**Time:** Under 1 minute.

**Steps:**

```bash
aws eks update-kubeconfig --region eu-central-1 --name petclinic-dev

kubectl rollout undo deployment/customers-service -n petclinic-dev
kubectl rollout status deployment/customers-service -n petclinic-dev --timeout=180s
```

Target a specific revision if the previous one is also bad:
```bash
kubectl rollout history deployment/customers-service -n petclinic-dev
kubectl rollout undo deployment/customers-service -n petclinic-dev --to-revision=<n>
```

> **This is not durable.** ArgoCD runs with `selfHeal: true` and will re-apply the Git state —
> typically within ~3 minutes — putting the bad image straight back. Either
> [pause auto-sync](#procedure-stop-the-bleeding--pause-auto-sync) first or follow immediately with
> a [GitOps rollback](#procedure-gitops-rollback-preferred).

---

## Procedure: Stop the Bleeding — Pause Auto-Sync

**When:** You need the cluster to stop tracking `main` while you sort out the correct tag, or CI
keeps dispatching broken builds.
**Who:** On-call engineer with ArgoCD access.
**Time:** Immediate.

```bash
# Freeze one service
argocd app set customers-service-dev --sync-policy none

# ... perform the emergency or GitOps rollback ...

# Unfreeze once main is known-good
argocd app set customers-service-dev --sync-policy automated --self-heal --auto-prune
```

If CI itself is the problem, disable the workflow so it stops pushing tag commits:
```bash
gh workflow disable update-image-tags.yml --repo <owner>/petclinic-platform
# re-enable with: gh workflow enable update-image-tags.yml --repo <owner>/petclinic-platform
```

---

## Verification

Run all four. The rollback is not done until every one passes.

```bash
# 1. Git holds the intended tag
yq '.image.tag' helm-values/customers-service.yaml

# 2. ArgoCD is Synced + Healthy
argocd app get customers-service-dev

# 3. Running pods use the expected image
kubectl get pods -n petclinic-dev -l app.kubernetes.io/name=customers-service \
  -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.containers[0].image}{"\n"}{end}'

# 4. The service reports healthy
kubectl rollout status deployment/customers-service -n petclinic-dev --timeout=180s
kubectl exec -n petclinic-dev deploy/customers-service -- \
  wget -qO- http://localhost:8081/actuator/health
```

Then run the end-to-end check:
```bash
bash scripts/smoke-test.sh petclinic-dev
```

---

## Testing the Rollback Path

Exercise this quarterly and after any change to `update-image-tags.yml`.

1. Note the current good tag:
   ```bash
   GOOD=$(yq '.image.tag' helm-values/vets-service.yaml); echo "$GOOD"
   ```
2. Introduce a deliberately bad tag and push:
   ```bash
   yq -i '.image.tag = "deadbee"' helm-values/vets-service.yaml
   git commit -am "test: rollback drill — bad tag for vets-service"
   git push origin main
   ```
3. Confirm the failure mode — ArgoCD syncs, pods enter `ImagePullBackOff`:
   ```bash
   kubectl get pods -n petclinic-dev -l app.kubernetes.io/name=vets-service -w
   ```
   The old ReplicaSet keeps serving traffic; the rolling update stalls rather than taking the
   service down. That is the expected blast radius for a bad tag.
4. Roll back and confirm recovery:
   ```bash
   git revert --no-edit HEAD && git push origin main
   argocd app sync vets-service-dev
   ```
5. Record the wall-clock time from bad push to green in the drill log.

---

## Known Traps

- **`kubectl rollout undo` silently reverts.** `selfHeal: true` re-applies Git within ~3 minutes.
  Never treat a `kubectl` rollback as finished work.
- **The next CI dispatch overwrites your revert.** `update-image-tags.yml` sets `image.tag` from
  the dispatch payload, so any push to the app repo's `main` re-tags the services. If the app repo
  still contains the bad commit, revert it there too — otherwise you are racing CI.
- **All 8 services are re-tagged on every dispatch.** The current workflow writes the payload SHA
  into all eight values files, not just the services that were rebuilt. A rollback that reverts one
  tag-update commit therefore moves all eight. Check the full diff before reverting:
  ```bash
  git show --stat <bad-tag-commit-sha>
  ```
- **Old images expire.** ECR keeps the last 10 images per repo; a "known-good" SHA from weeks ago
  may no longer exist. Verify with `aws ecr describe-images` before pushing the tag.
- **Config and discovery servers roll everything.** Rolling back `config-server` or
  `discovery-server` restarts their dependents via init-container waits. Expect 3–5 minutes of
  partial unavailability, and roll those back outside peak use where possible.
- **`prune: true`.** Reverting a commit that added a resource will delete that resource from the
  cluster, not just stop managing it.

---

## Related

- [`docs/runbook.md`](./runbook.md) — day-to-day operations, including the short-form rollback procedure
- [`docs/incident-playbook.md`](./incident-playbook.md) — escalation and RCA
- [`docs/technical-spec.md`](./technical-spec.md#cicd-pipeline) — CI/CD pipeline and image tag mechanism
- [`.github/workflows/update-image-tags.yml`](../.github/workflows/update-image-tags.yml) — the workflow that writes tags
- [`terraform/modules/github-oidc/`](../terraform/modules/github-oidc/) — CI's AWS credentials (PETPLAT-52)
