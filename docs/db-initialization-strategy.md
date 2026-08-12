# Database Initialization Strategy

**Last Updated:** 2026-06-02
**Jira:** PETPLAT-24
**Epic:** E-5 Database (RDS MySQL)

## Purpose

Documents how the shared `petclinic` MySQL database gets its schema initialized for the three database-backed services (customers, visits, vets — 7 tables total).

---

## Database Layout

All three services share a single RDS MySQL 8.0 instance with one database: `petclinic`.

| Service | Tables Created | Foreign Key Dependencies |
|---------|---------------|--------------------------|
| customers-service | `types`, `owners`, `pets` | None (source tables) |
| vets-service | `vets`, `specialties`, `vet_specialties` | None (independent) |
| visits-service | `visits` | `pet_id` → `pets(id)` in customers schema |

**Critical:** `visits.pet_id` references `pets.id`, which is owned by the customers schema. Customers service schema must be initialized before visits service.

---

## Initialization Strategy: Spring Boot Auto-Init

**Approach chosen:** Spring Boot automatic schema initialization via `spring.sql.init.mode=always` on first startup with the `mysql` Spring profile active.

Each service contains its SQL scripts at `src/main/resources/db/mysql/`:
- `spring-petclinic-customers-service/src/main/resources/db/mysql/schema.sql`
- `spring-petclinic-vets-service/src/main/resources/db/mysql/schema.sql`
- `spring-petclinic-visits-service/src/main/resources/db/mysql/schema.sql`

Each script begins with:
```sql
CREATE DATABASE IF NOT EXISTS petclinic;
USE petclinic;
```

Spring Boot initializes the schema on startup when `spring.sql.init.mode=always` and the `mysql` profile is active. This is the default behavior in the app's `application-mysql.properties`.

**Why auto-init:** The app is already wired for it. No external tooling or init jobs required. The scripts are idempotent (use `CREATE TABLE IF NOT EXISTS`).

---

## Initialization Order (Critical)

Enforce startup order via Kubernetes deployment sequencing:

1. **Deploy customers-service first** — creates `types`, `owners`, `pets` tables
2. **Deploy vets-service** — creates `vets`, `specialties`, `vet_specialties` (independent, can be parallel with customers)
3. **Deploy visits-service last** — creates `visits` table with FK `pet_id → pets(id)`

The Kubernetes init containers in each deployment enforce Config Server and Discovery Server readiness, but **not** cross-service DB initialization order. The deployment order is enforced by ArgoCD sync waves or by manual deployment sequencing.

```
customers-service (wave 1) → visits-service (wave 2)
vets-service      (wave 1) ↗
```

---

## Connection String

```
jdbc:mysql://{rds-endpoint}:3306/petclinic
```

Example:
```
jdbc:mysql://petclinic-dev-mysql.abc123.eu-central-1.rds.amazonaws.com:3306/petclinic
```

Set in each DB service's Kubernetes ConfigMap:

```yaml
SPRING_DATASOURCE_URL: "jdbc:mysql://{rds-endpoint}:3306/petclinic"
```

Credentials (`SPRING_DATASOURCE_USERNAME`, `SPRING_DATASOURCE_PASSWORD`) come from the Kubernetes Secret synced by External Secrets Operator from `petclinic/{env}/rds-credentials` in AWS Secrets Manager.

---

## Verifying Initialization

After deploying, confirm tables were created:

```bash
# Run a MySQL debug pod (from any EKS node)
kubectl run -it --rm debug --image=mysql:8 --restart=Never -n petclinic-dev -- \
  mysql -h {rds-endpoint} -u petclinic -p{password} petclinic -e "SHOW TABLES;"
```

Expected output (7 tables):
```
owners
pets
specialties
types
vet_specialties
vets
visits
```

---

## Re-initialization

Schema scripts use `CREATE TABLE IF NOT EXISTS` — safe to re-run. If a full reset is needed:

1. Drop the database: `DROP DATABASE petclinic;`
2. Restart all three DB services — Spring Boot recreates and re-initializes on startup
3. Restore data from RDS backup if needed (backup retention: 7 days dev, 30 days prod)
