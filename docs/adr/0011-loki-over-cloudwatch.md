# ADR-0011: In-Cluster Logging (Loki) Over CloudWatch Logs

**Status:** Accepted
**Date:** 2026-02-01

**Context:**
Container logs need centralized aggregation. AWS CloudWatch Logs is the native AWS solution (requires FluentBit DaemonSet with IRSA role, costs ~$0.50/GB ingestion + $0.03/GB storage). Loki is an open-source alternative that runs in-cluster.

**Decision:**
Loki for log aggregation running in-cluster, with FluentBit DaemonSet forwarding logs to Loki over HTTP. No AWS IAM role needed for log shipping.

**Consequences:**
- Saves ~$20–50/month vs. CloudWatch Logs for 8 services generating moderate log volume
- No IRSA role needed for FluentBit — purely in-cluster HTTP
- Grafana serves as the UI for both metrics (Prometheus) and logs (Loki) — single pane of glass
- Loki requires persistent storage (EBS PVC via EBS CSI Driver)
- Logs lost if Loki pod is deleted without PVC backup (acceptable for learning)
- Loki's LogQL is different from CloudWatch Insights QL (slight learning curve)
