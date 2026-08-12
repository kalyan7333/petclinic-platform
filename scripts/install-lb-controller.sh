#!/usr/bin/env bash
# Install the AWS Load Balancer Controller on EKS via Helm.
# PETPLAT-29
#
# Usage:
#   bash scripts/install-lb-controller.sh <cluster-name> <role-arn> <vpc-id>
#
# Or get all three values from Terraform output:
#   bash $(terraform -chdir=terraform/environments/dev output -raw install_lb_controller_command)
#
# Version note:
#   APP_VERSION is the controller application version (e.g. v2.8.1) used for CRD URLs.
#   CHART_VERSION is the Helm chart version (e.g. 1.8.1) — DIFFERENT numbering scheme.
#   Always use APP_VERSION when referencing GitHub tags for CRDs — using the chart version
#   produces a 404 because the controller repo tags only use the v2.x.x format.

set -euo pipefail

APP_VERSION="v2.8.1"
NAMESPACE="kube-system"

CLUSTER_NAME="${1:?Error: cluster-name required. Usage: $0 <cluster-name> <role-arn> <vpc-id>}"
ROLE_ARN="${2:?Error: role-arn required. Usage: $0 <cluster-name> <role-arn> <vpc-id>}"
VPC_ID="${3:?Error: vpc-id required. Usage: $0 <cluster-name> <role-arn> <vpc-id>}"

echo "==> Installing AWS Load Balancer Controller ${APP_VERSION}"
echo "    Cluster : ${CLUSTER_NAME}"
echo "    Role ARN: ${ROLE_ARN}"
echo "    VPC ID  : ${VPC_ID}"
echo ""

# Step 1: Install CRDs
# Use the controller app version tag (v2.8.1), NOT the Helm chart version (1.8.1).
# The kubernetes-sigs/aws-load-balancer-controller repo uses v2.x.x tags.
# The aws/eks-charts repo uses aws-load-balancer-controller-1.x.x tags — different scheme.
echo "==> Applying CRDs (app version ${APP_VERSION})..."
kubectl apply -k "github.com/kubernetes-sigs/aws-load-balancer-controller/helm/aws-load-balancer-controller/crds?ref=${APP_VERSION}"

# Step 2: Add the eks Helm repository
echo "==> Adding eks Helm repository..."
helm repo add eks https://aws.github.io/eks-charts
helm repo update eks

# Step 3: Install or upgrade the controller via Helm
echo "==> Installing aws-load-balancer-controller via Helm..."
helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
  --namespace "${NAMESPACE}" \
  --set clusterName="${CLUSTER_NAME}" \
  --set serviceAccount.create=true \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn=${ROLE_ARN}" \
  --set region=eu-central-1 \
  --set vpcId="${VPC_ID}" \
  --set createIngressClassResource=true \
  --set ingressClass=alb \
  --skip-crds \
  --wait \
  --timeout 5m

echo ""
echo "==> AWS Load Balancer Controller installed successfully."
echo ""
echo "    Verify controller pods:"
echo "      kubectl get deployment -n ${NAMESPACE} aws-load-balancer-controller"
echo ""
echo "    Next steps:"
echo "    1. Update k8s/base/ingress/ingress.yaml — replace REPLACE_WITH_ACM_CERT_ARN"
echo "       with the ACM certificate ARN from Terraform output: acm_certificate_arn"
echo "    2. Apply the ingress: kubectl apply -f k8s/base/ingress/ingress.yaml -n petclinic-dev"
echo "    3. Get ALB hostname: kubectl get ingress -n petclinic-dev petclinic-ingress -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'"
echo "    4. Set alb_dns_name in tfvars and re-apply Terraform to create the Route 53 alias record."
