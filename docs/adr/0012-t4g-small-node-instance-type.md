# ADR-0012: t4g.small for EKS node groups

**Status:** Accepted
**Date:** 2026-08-04

**Context:**

The AWS account is on the **FREE** account plan (active, expires 2026-12-23).
That plan refuses to launch any EC2 instance type not marked
`free-tier-eligible`, returning:

```
AsgInstanceLaunchFailures: Could not launch On-Demand Instances.
InvalidParameterCombination - The specified instance type is not eligible for Free Tier.
```

The failure surfaces as an EKS node group stuck in `CREATE_FAILED`, roughly 30
minutes after `terraform apply` starts — the Auto Scaling group retries before
giving up, so the feedback is slow and easy to misread as a capacity problem.

Free-tier-eligible types in eu-central-1:

| Type | Arch | vCPU | Memory |
|------|------|------|--------|
| `t4g.small` | arm64 | 2 | 2 GiB |
| `t4g.micro` | arm64 | 2 | 1 GiB |
| `t3.small` | x86_64 | 2 | 2 GiB |
| `t3.micro` | x86_64 | 2 | 1 GiB |
| `c7i-flex.large` | x86_64 | 2 | 4 GiB |
| `m7i-flex.large` | x86_64 | 2 | 8 GiB |

All service images are built `linux/arm64` for Graviton (see CLAUDE.md, Docker
Image Details), which rules out every x86_64 option regardless of size.

**Decision:**

Use `t4g.small` for EKS node groups in every environment, with
`node_ami_type = "AL2023_ARM_64_STANDARD"`. It is the largest Graviton type the
FREE plan permits. This is the default in `terraform/modules/eks/variables.tf`;
environments must not override it upward while the account remains on the FREE
plan.

Verify before changing the type:

```bash
aws ec2 describe-instance-types --region eu-central-1 \
  --filters Name=free-tier-eligible,Values=true \
  --query 'InstanceTypes[].{type:InstanceType,arch:ProcessorInfo.SupportedArchitectures[0],memMiB:MemoryInfo.SizeInMiB}' \
  --output table
```

**Consequences:**

Positive:
- Node groups launch successfully and stay within the free-tier envelope.
- Graviton/arm64 is preserved, so no change to the image build pipeline.
- The constraint is enforced by the module default rather than per environment.

Negative:
- 2 GiB per node is tight. Two nodes give ~4 GiB before the kubelet, CNI,
  CoreDNS and the EBS CSI driver take their share. The 8 services request 128Mi
  each but are limited to 512Mi, so the cluster schedules close to its ceiling.
- Scale out, not up: raise `node_desired_size` when capacity runs short.
  Switching to a larger type requires moving the account off the FREE plan.
- `t4g.medium` (4 GiB), the natural next size, is **not** eligible — it was the
  original override in `terraform/environments/dev/main.tf` and the cause of the
  failure above.

**Related:** [ADR-0002](0002-eks-over-ecs.md) (EKS over ECS)
