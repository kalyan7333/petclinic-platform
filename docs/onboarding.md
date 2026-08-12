# Onboarding Guide

**Last Updated:** 2026-05-26
**Purpose:** Get a new engineer productive on the Petclinic Platform in ≤ 90 minutes.

## Table of Contents
1. [Prerequisites](#prerequisites)
2. [Initial Setup](#initial-setup)
3. [Explore the Running App](#explore-the-running-app)
4. [Make a Change and Deploy](#make-a-change-and-deploy)

---

## Prerequisites

**Time: 20 minutes**

### Tools to install
```bash
# Homebrew (macOS)
brew install awscli kubectl helm argocd terraform jq yq git
brew install --cask docker

# Verify versions
aws --version           # >= 2.x
kubectl version --client  # >= 1.29
helm version            # >= 3.x
terraform version       # >= 1.6
```

### AWS Access
1. Request AWS IAM access from the team lead (need: EKS describe, ECR read, Secrets Manager read)
2. Configure AWS CLI:
   ```bash
   aws configure
   # AWS Access Key ID: [provided by team lead]
   # Default region: eu-central-1
   # Default output: json
   ```
3. Verify: `aws sts get-caller-identity`

### Cluster Access
```bash
aws eks update-kubeconfig --name petclinic-dev --region eu-central-1
kubectl get nodes   # Should show 2 Ready nodes
```

### Clone the Repos
```bash
git clone {PLATFORM_REPO_URL} petclinic-platform
git clone {APP_REPO_URL} spring-petclinic-microservices
```

---

## Initial Setup

**Time: 10 minutes**

### Access ArgoCD
```bash
kubectl port-forward svc/argocd-server -n argocd 8443:443
# Open https://localhost:8443
# Username: admin
# Password: kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath='{.data.password}' | base64 -d
```

### Access Grafana
```bash
kubectl port-forward svc/grafana -n monitoring 3000:3000
# Open http://localhost:3000
# Username: admin
# Password: kubectl get secret grafana-admin -n monitoring -o jsonpath='{.data.password}' | base64 -d
```

---

## Explore the Running App

**Time: 20 minutes**

### Check all services are healthy
```bash
kubectl get deployments -n petclinic-dev
kubectl get pods -n petclinic-dev

# Port-forward API Gateway to test locally
kubectl port-forward svc/api-gateway 8080:8080 -n petclinic-dev
# Open http://localhost:8080
```

### Check service discovery
```bash
kubectl port-forward svc/discovery-server 8761:8761 -n petclinic-dev
# Open http://localhost:8761 — all 8 services should be registered
```

### Check dashboards
1. Open Grafana → Dashboards → Petclinic Overview
2. Check Prometheus targets: `kubectl port-forward svc/prometheus 9090:9090 -n monitoring`
3. Open http://localhost:9090/targets — all petclinic services should show UP

---

## Make a Change and Deploy

**Time: 30 minutes**

### Local change → Dev deployment
1. Make a code change in `spring-petclinic-microservices/spring-petclinic-{service}/`
2. Push to main — GitHub Actions builds and pushes to ECR
3. `update-image-tags.yml` workflow updates `helm-values/{service}.yaml`
4. ArgoCD auto-syncs → new pod deployed in petclinic-dev
5. Verify: `kubectl rollout status deployment/{service} -n petclinic-dev`

### Deploy to prod
1. Review the diff in ArgoCD UI (shows what will change)
2. Click Sync on the application in ArgoCD UI (manual approval required)
3. Monitor rollout: `kubectl rollout status deployment/{service} -n petclinic-prod`

### Key contacts
- Platform issues: create GitHub issue in petclinic-platform repo
- Access requests: contact team lead
- On-call: see PagerDuty rotation (link in team wiki)
