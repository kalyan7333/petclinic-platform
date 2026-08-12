# ADR-0006: Single-AZ RDS for Both Environments

**Status:** Accepted
**Date:** 2026-01-15

**Context:**
Multi-AZ RDS provides automatic failover during AZ outages. It roughly doubles the cost ($15–30/month more for db.t4g.micro).

**Decision:**
Single-AZ RDS for both dev and prod environments. This is a cost-optimization decision for a learning platform.

**Consequences:**
- Saves ~$15–30/month per environment
- No automatic failover; AZ outage = downtime until RDS recovers
- Acceptable for a learning platform with no SLA commitments
- Students should know: in real production with SLA requirements, enable Multi-AZ
- Backup retention (30 days prod) provides data protection even without Multi-AZ
