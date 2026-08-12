#!/usr/bin/env bash
#
# validate-helm.sh — PETPLAT-110
#
# Validates the generic Helm chart for all 8 services in dev:
#   1. helm lint on the chart
#   2. helm template for all 8 services
#   3. assertions on the rendered output (ports, replicas, HPA/PDB, namespace,
#      ECR project, secret refs, probes, security context) — these encode the
#      k8s/base + k8s/overlays manifests that the chart must reproduce
#   4. kubectl apply --dry-run=client on the rendered output
#
# Step 4 needs a reachable API server: `kubectl apply --dry-run=client` still
# performs API discovery to resolve each kind. When no cluster is reachable
# (the usual case after scripts/stop-env.sh) it is reported as SKIPPED, not
# passed, and steps 1-3 still run.
#
# Usage:
#   bash scripts/validate-helm.sh                        # all 8 releases
#   bash scripts/validate-helm.sh --service vets-service
#   bash scripts/validate-helm.sh --env dev --service vets-service
set -o pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

CHART_DIR="helm/petclinic-service"
VALUES_DIR="helm-values"
RENDER_DIR="$(mktemp -d)"
trap 'rm -rf "$RENDER_DIR"' EXIT

SERVICES=(config-server discovery-server api-gateway customers-service visits-service vets-service genai-service admin-server)
ENVS=(dev)

while [ $# -gt 0 ]; do
  case "$1" in
    --env)     ENVS=("$2"); shift 2 ;;
    --service) SERVICES=("$2"); shift 2 ;;
    -h|--help)
      sed -n '2,20p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    *)
      echo "Unknown argument: $1" >&2
      echo "Usage: $0 [--env dev] [--service <name>]" >&2
      exit 2 ;;
  esac
done

for e in "${ENVS[@]}"; do
  [ -f "${VALUES_DIR}/${e}.yaml" ] || { echo "No such environment: $e" >&2; exit 2; }
done
for s in "${SERVICES[@]}"; do
  [ -f "${VALUES_DIR}/${s}.yaml" ] || { echo "No such service: $s" >&2; exit 2; }
done

# Expected rendered values, derived from k8s/base/ and k8s/overlays/dev/.
# service|port|replicas
EXPECTED=(
  "config-server|8888|1"
  "discovery-server|8761|1"
  "api-gateway|8080|1"
  "customers-service|8081|1"
  "visits-service|8082|1"
  "vets-service|8083|1"
  "genai-service|8084|1"
  "admin-server|9090|1"
)

PASS=0
FAIL=0
SKIP=0
CASE_FAILS=0
FAILED_CASES=()

red()   { printf '\033[31m%s\033[0m\n' "$1"; }
green() { printf '\033[32m%s\033[0m\n' "$1"; }
yellow(){ printf '\033[33m%s\033[0m\n' "$1"; }

fail() {
  red "    FAIL: $1"
  FAIL=$((FAIL + 1))
  CASE_FAILS=$((CASE_FAILS + 1))
  FAILED_CASES+=("$CASE: $1")
}

# Assertions below use awk/grep only, so the script needs nothing beyond
# helm, kubectl and bash 3.2 (the macOS system bash).

# Extract the document(s) of a given kind from a multi-doc rendered file.
doc_of_kind() {
  awk -v want="$1" '
    BEGIN { RS="\n---\n"; ORS="" }
    $0 ~ "(^|\n)kind: " want "(\n|$)" { print $0 "\n" }
  ' "$2"
}

field() { # field <file> <indent-anchored key>  -> first value
  grep -m1 -E "^[[:space:]]*$2:" "$1" | sed -E "s/^[[:space:]]*$2:[[:space:]]*//" | tr -d '"'
}

expected_for() {
  local svc="$1"
  for row in "${EXPECTED[@]}"; do
    [ "${row%%|*}" = "$svc" ] && { echo "$row"; return 0; }
  done
  return 1
}

echo "=============================================="
echo " 1. helm lint"
echo "=============================================="
LINT_FAILED=false
helm lint "$CHART_DIR" || LINT_FAILED=true
for env in "${ENVS[@]}"; do
  for svc in "${SERVICES[@]}"; do
    helm lint "$CHART_DIR" \
      -f "${VALUES_DIR}/${svc}.yaml" \
      -f "${VALUES_DIR}/${env}.yaml" >/dev/null 2>&1 \
      || { red "helm lint failed for ${svc}/${env}"; LINT_FAILED=true; }
  done
done
if $LINT_FAILED; then
  red "helm lint failed"
  exit 1
fi
green "helm lint passed (chart + all service/environment value combinations)"
echo

# Is an API server reachable? Decides whether step 4 runs or is skipped.
KUBECTL_AVAILABLE=false
if kubectl api-resources --request-timeout=10s >/dev/null 2>&1; then
  KUBECTL_AVAILABLE=true
  green "Cluster reachable ($(kubectl config current-context 2>/dev/null)) — kubectl dry-run enabled"
else
  yellow "No reachable cluster — kubectl apply --dry-run=client will be SKIPPED."
  yellow "  Start the environment first:  bash scripts/start-env.sh dev"
  yellow "  (kubectl needs API discovery even for a client-side dry run)"
fi
echo

echo "=============================================="
echo " 2-4. render, assert, dry-run"
echo "=============================================="

for env in "${ENVS[@]}"; do
  for svc in "${SERVICES[@]}"; do
    CASE="${svc}/${env}"
    CASE_FAILS=0
    echo "--- ${CASE}"

    row="$(expected_for "$svc")" || { fail "no expectations defined for $svc"; continue; }
    IFS='|' read -r _ exp_port exp_replicas <<<"$row"

    out="${RENDER_DIR}/${svc}-${env}.yaml"
    if ! helm template "$svc" "$CHART_DIR" \
        -f "${VALUES_DIR}/${svc}.yaml" \
        -f "${VALUES_DIR}/${env}.yaml" > "$out" 2>"${out}.err"; then
      fail "helm template: $(head -5 "${out}.err" | tr '\n' ' ')"
      continue
    fi

    deploy="${RENDER_DIR}/${svc}-${env}.deploy"
    doc_of_kind Deployment "$out" > "$deploy"

    # --- namespace
    exp_ns="petclinic-${env}"
    [ "$(field "$deploy" namespace)" = "$exp_ns" ] \
      || fail "namespace: expected $exp_ns, got $(field "$deploy" namespace)"

    # --- container + service port
    grep -q "containerPort: ${exp_port}$" "$deploy" \
      || fail "containerPort: expected ${exp_port}"
    doc_of_kind Service "$out" | grep -q "port: ${exp_port}$" \
      || fail "service port: expected ${exp_port}"

    # --- replicas
    got_replicas="$(field "$deploy" replicas)"
    [ "$got_replicas" = "$exp_replicas" ] \
      || fail "replicas: expected $exp_replicas, got $got_replicas"

    # --- image: correct per-environment ECR project, never :latest
    img="$(grep -m1 -E "^\s+image: .*/${svc}:" "$deploy" | sed -E 's/^\s+image: //')"
    case "$img" in
      */petclinic-${env}/${svc}:*) ;;
      *) fail "image: expected .../petclinic-${env}/${svc}:<tag>, got '${img}'" ;;
    esac
    case "$img" in
      *:latest) fail "image tag is 'latest' — must be a commit SHA (CLAUDE.md)" ;;
    esac

    # --- probes: all three present, port matches
    for probe in startupProbe readinessProbe livenessProbe; do
      grep -q "${probe}:" "$deploy" || fail "missing ${probe}"
    done
    [ "$(grep -c "port: ${exp_port}$" "$deploy")" -ge 3 ] \
      || fail "probes do not all target port ${exp_port}"

    # --- security context (PSA baseline/restricted-warn namespaces)
    grep -q "runAsNonRoot: true" "$deploy"          || fail "missing runAsNonRoot"
    grep -q "type: RuntimeDefault" "$deploy"        || fail "missing seccompProfile RuntimeDefault"
    grep -q "allowPrivilegeEscalation: false" "$deploy" || fail "missing allowPrivilegeEscalation: false"

    # --- resources: requests and limits on every container (one `image:` line
    #     per container, init containers included)
    n_containers="$(grep -cE "^[[:space:]]+image: " "$deploy")"
    n_resources="$(grep -cE "^[[:space:]]+resources:" "$deploy")"
    [ "$n_resources" -ge "$n_containers" ] \
      || fail "not every container has resources (${n_resources} blocks / ${n_containers} containers)"
    [ "$(grep -cE "^[[:space:]]+requests:" "$deploy")" -ge "$n_containers" ] \
      || fail "not every container has resource requests"
    [ "$(grep -cE "^[[:space:]]+limits:" "$deploy")" -ge "$n_containers" ] \
      || fail "not every container has resource limits"

    # --- secret refs come from ESO-managed secrets, never inline
    case "$svc" in
      customers-service|visits-service|vets-service)
        grep -q "name: rds-credentials" "$deploy" || fail "missing rds-credentials secret ref"
        grep -q "key: username" "$deploy"         || fail "missing rds-credentials key 'username'"
        grep -q "key: password" "$deploy"         || fail "missing rds-credentials key 'password'"
        ;;
      genai-service)
        grep -q "name: openai-api-key" "$deploy"   || fail "missing openai-api-key secret ref"
        grep -q "key: OPENAI_API_KEY" "$deploy"    || fail "missing key 'OPENAI_API_KEY'"
        ;;
    esac
    grep -qiE "^\s+(password|api[_-]?key):" "$out" \
      && fail "possible inline secret in rendered output"

    # --- HPA / PDB: conditional templates, disabled in dev
    grep -q "^kind: HorizontalPodAutoscaler" "$out" && fail "HPA rendered but dev disables autoscaling"
    grep -q "^kind: PodDisruptionBudget" "$out" && fail "PDB rendered but dev runs a single replica"

    # --- resource names must not track the Helm release name. ArgoCD names the
    #     release {service}-dev, and service DNS, init containers, the Ingress
    #     backend and the NetworkPolicies all reference the bare service name.
    alt="${RENDER_DIR}/${svc}-${env}.relname"
    if helm template "${svc}-${env}" "$CHART_DIR" \
        -f "${VALUES_DIR}/${svc}.yaml" \
        -f "${VALUES_DIR}/${env}.yaml" > "$alt" 2>/dev/null; then
      grep -qE "^  name: ${svc}$" "$alt" \
        || fail "resource names follow the release name — set fullnameOverride: ${svc}"
      grep -qE "^  name: ${svc}-${env}$" "$alt" \
        && fail "resource names follow the release name — set fullnameOverride: ${svc}"
    fi

    # --- kubectl apply --dry-run=client
    if $KUBECTL_AVAILABLE; then
      if ! kubectl apply --dry-run=client -f "$out" >/dev/null 2>"${out}.kubectl"; then
        fail "kubectl apply --dry-run=client: $(head -3 "${out}.kubectl" | tr '\n' ' ')"
      fi
    else
      SKIP=$((SKIP + 1))
    fi

    if [ "$CASE_FAILS" -eq 0 ]; then
      green "    OK"
      PASS=$((PASS + 1))
    fi
  done
done

echo
echo "=============================================="
echo " Summary"
echo "=============================================="
echo "  passed:  $PASS"
echo "  failed:  $FAIL"
$KUBECTL_AVAILABLE || echo "  kubectl dry-run SKIPPED for $SKIP render(s) — no reachable cluster"

if [ "$FAIL" -gt 0 ]; then
  echo
  red "Failures:"
  for f in "${FAILED_CASES[@]}"; do echo "  - $f"; done
  exit 1
fi

green "All Helm templates valid."
