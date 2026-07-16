# EKS Module

Provisions the EKS control plane, OIDC provider (for IRSA), a managed node group
on ARM/Graviton nodes, EKS-managed add-ons, and cluster access for the deploying
principal. Covers PETPLAT-12, PETPLAT-13, PETPLAT-14, and PETPLAT-84.

Nodes run in the environment's **public subnets** (all-public design, ADR-0001).
Access control is enforced by security groups passed in from the VPC module.

## What it creates

- **Cluster** (`aws_eks_cluster`) — K8s 1.29, public + private endpoint, control-plane
  logging (`api`, `audit`, `authenticator`, `controllerManager`, `scheduler`),
  `API_AND_CONFIG_MAP` auth mode.
- **Cluster IAM role** with `AmazonEKSClusterPolicy`.
- **OIDC provider** from the cluster issuer — required for IRSA.
- **Node IAM role** with `AmazonEKSWorkerNodePolicy`, `AmazonEKS_CNI_Policy`,
  `AmazonEC2ContainerRegistryReadOnly`.
- **Launch template** — attaches the dedicated EKS Node security group, enforces
  IMDSv2 (`http_tokens = required`), and encrypts the root EBS volume (gp3).
- **Managed node group** — `t4g.small` (AL2_ARM_64), min 2 / max 4 / desired 2.
- **Managed add-ons** — `coredns`, `kube-proxy`, `vpc-cni`, `aws-ebs-csi-driver`
  (with its own IRSA role). Versions are **pinned**, not `latest`.
- **Access entry** granting the deploying IAM principal cluster-admin.

## Accessing the cluster (PETPLAT-14)

After `terraform apply`, update your kubeconfig using the `kubeconfig_command`
output:

```bash
terraform output -raw kubeconfig_command
# aws eks update-kubeconfig --name petclinic-dev --region eu-central-1

aws eks update-kubeconfig --name petclinic-dev --region eu-central-1
kubectl get nodes
```

The deploying principal is granted admin automatically via an EKS **access entry**
plus `AmazonEKSClusterAdminPolicy`.

### Adding additional users or roles

This cluster uses `API_AND_CONFIG_MAP` authentication mode, so grant access with
EKS **access entries** (no need to edit the `aws-auth` ConfigMap). Add entries
alongside the `deployer` entry in `main.tf`:

```hcl
resource "aws_eks_access_entry" "teammate" {
  cluster_name  = aws_eks_cluster.this.name
  principal_arn = "arn:aws:iam::<account>:role/<role-name>"
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "teammate_view" {
  cluster_name  = aws_eks_cluster.this.name
  principal_arn = "arn:aws:iam::<account>:role/<role-name>"
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSViewPolicy"

  access_scope {
    type = "cluster"
  }

  depends_on = [aws_eks_access_entry.teammate]
}
```

Common policy ARNs: `AmazonEKSClusterAdminPolicy` (full admin),
`AmazonEKSAdminPolicy` (namespace admin, scope to namespaces),
`AmazonEKSEditPolicy` (edit), `AmazonEKSViewPolicy` (read-only).

## Upgrading add-on versions (PETPLAT-84)

Add-on versions are pinned in `var.addon_versions` (defaults target K8s 1.29).
**Never** use `latest` — upgrades must be deliberate and reviewed.

To find compatible versions for a given cluster version:

```bash
aws eks describe-addon-versions \
  --kubernetes-version 1.29 \
  --addon-name coredns \
  --query 'addons[].addonVersions[].addonVersion' --output table
```

Then bump the value in the environment's `module "eks"` block (or the module
default) and run the standard workflow:

```bash
terraform plan -out plan.out
terraform apply plan.out
```

When bumping `cluster_version`, update all four add-on versions in the same change.

## Key variables

| Variable | Default | Notes |
|----------|---------|-------|
| `cluster_version` | `1.29` | Spec-pinned for dev and prod |
| `public_access_cidrs` | `["0.0.0.0/0"]` | Restrict to office/VPN CIDRs where possible |
| `node_instance_types` | `["t4g.small"]` | ARM/Graviton free trial |
| `node_min/max/desired_size` | `2 / 4 / 2` | |
| `node_disk_size` | `20` | GB, encrypted gp3 root volume |
| `addon_versions` | K8s 1.29 versions | Pinned; see upgrade section |

## Key outputs

`cluster_name`, `cluster_endpoint`, `cluster_ca_certificate` (sensitive),
`oidc_provider_arn`, `oidc_provider_url`, `node_group_name`, `node_role_arn`,
`ebs_csi_role_arn`, `kubeconfig_command`.
