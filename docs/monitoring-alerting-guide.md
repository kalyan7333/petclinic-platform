# Monitoring and Alerting Guide

**Last Updated:** 2026-05-26
**Purpose:** Reference for the Petclinic observability stack — dashboards, alerts, log queries, and on-call procedures.

## Alert Rules

| Alert | Condition | Severity | Action |
|-------|-----------|----------|--------|
| ServiceDown | `up == 0` for 1 min | critical | Page on-call immediately |
| HighErrorRate | >5% 5xx for 5 min | warning | Investigate within 1 hour |
| HighLatency | p95 > 500ms for 5 min | warning | Investigate within 1 hour |
| PodRestartLoop | >3 restarts in 15 min | critical | Page on-call immediately |
| HighMemoryUsage | >80% of limit for 5 min | warning | Consider increasing limits |

## Alert Routing

Alerts are routed through Alertmanager:
- **Critical** → immediate email to on-call (10s group wait)
- **Warning** → batched email (30s group wait, 5m group interval)

Update `k8s/base/observability/alertmanager/deployment.yaml` to configure Slack/PagerDuty receivers.

## Grafana Access

```bash
kubectl port-forward svc/grafana -n monitoring 3000:3000
# http://localhost:3000
# Admin password: kubectl get secret grafana-admin -n monitoring -o jsonpath='{.data.password}' | base64 -d
```

**Key dashboards:**
- **Petclinic Overview** — all services: RPS, error rate, p95 latency
- **JVM Metrics** — heap, GC, threads per service
- **Node metrics** — CPU, memory, disk per EKS node

## Loki Log Queries (LogQL)

```logql
# All errors from a specific service
{namespace="petclinic-dev", container="customers-service"} |= "ERROR"

# Database connection errors
{namespace="petclinic-dev"} |= "Unable to acquire JDBC"

# All logs from a pod
{namespace="petclinic-dev", pod=~"vets-service-.*"}

# Recent errors across all services
{namespace="petclinic-dev"} |= "ERROR" | json | line_format "{{.container}} {{.log}}"
```

## Silence/Acknowledge Alerts

**Via Alertmanager UI:**
```bash
kubectl port-forward svc/alertmanager -n monitoring 9093:9093
# http://localhost:9093
```

**Via amtool CLI:**
```bash
amtool silence add --alertname=HighLatency --duration=2h \
  --comment="Maintenance window" \
  --alertmanager.url=http://localhost:9093
```

## Adding New Alerts

1. Edit `k8s/base/observability/prometheus/configmap.yaml`, add rule under `alert-rules.yml`
2. Restart Prometheus: `kubectl rollout restart deployment/prometheus -n monitoring`
3. Verify rule appears at http://localhost:9090/rules
