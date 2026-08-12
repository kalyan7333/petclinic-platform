# ADR-0001: All-Public Subnet Design (No NAT Gateway)

**Status:** Accepted
**Date:** 2026-01-15

**Context:**
A standard production VPC uses private subnets for workloads + public subnets for ALB, with NAT Gateways allowing outbound internet access from private subnets. NAT Gateways cost ~$32-65/month per AZ.

**Decision:**
Use all-public subnets for all resources (EKS nodes, RDS, ALB). Security groups serve as the access control perimeter, fulfilling the same security role as private subnets in a learning environment.

**Consequences:**
- Saves ~$65–130/month per environment (no NAT Gateways)
- EKS nodes, RDS instances have public IPs but are protected by security groups
- RDS SG allows 3306 only from EKS node SG — equivalent protection to a private subnet
- Not suitable for regulated production workloads (PCI-DSS, HIPAA) without private subnets
- Students learn security group discipline, not just "private subnet security theater"
