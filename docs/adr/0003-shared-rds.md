# ADR-0003: Single Shared RDS Instance for All Services

**Status:** Accepted
**Date:** 2026-01-15

**Context:**
The three DB-backed services (customers, visits, vets) could each have their own RDS instance, or share one. Shared instance is cheaper. Analysis of the app's schema reveals cross-service FK: `visits.pet_id` → `pets.id` (owned by customers-service), confirming the shared DB assumption.

**Decision:**
Single RDS MySQL instance with a shared `petclinic` database. All three services connect to the same instance using the same credentials.

**Consequences:**
- Saves ~$15–30/month vs. 3 separate instances
- Single point of failure for all DB-backed services (acceptable for learning)
- No service isolation at the DB layer (acceptable given cross-service FKs already exist)
- In a proper microservices refactor, each service would have its own DB
