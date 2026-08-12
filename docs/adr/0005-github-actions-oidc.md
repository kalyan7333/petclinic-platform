# ADR-0005: GitHub Actions with OIDC Federation

**Status:** Accepted
**Date:** 2026-01-15

**Context:**
CI/CD needs AWS access to push images to ECR and update Helm values. Options: long-lived IAM access keys stored as GitHub Secrets, or OIDC federation (keyless authentication).

**Decision:**
OIDC federation — GitHub Actions assumes an IAM role via OIDC identity provider. No long-lived credentials stored anywhere.

**Consequences:**
- More secure: no secret rotation needed, credentials can't be leaked from GitHub Secrets
- IAM role trust policy scoped to specific repo and branch (`token.actions.githubusercontent.com`)
- Slight setup complexity (IAM OIDC provider + role)
- Industry best practice for CI/CD AWS authentication
