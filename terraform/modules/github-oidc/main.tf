# E-10: OIDC federation for GitHub Actions — PETPLAT-52
#
# Gives the CI workflow in the APPLICATION repo fork short-lived AWS credentials
# via web identity federation. No long-lived access keys are stored in GitHub.

locals {
  tags = merge(var.tags, { Component = "cicd" })

  oidc_issuer = "token.actions.githubusercontent.com"

  # The workflow that assumes this role (build-push.yml) runs in the application
  # repo, so the subject names that repo — not petclinic-platform. Pinning to a
  # single ref means PRs and other branches cannot mint credentials.
  allowed_subject = "repo:${var.github_owner}/${var.app_repository}:ref:refs/heads/${var.allowed_branch}"

  oidc_provider_arn = var.create_oidc_provider ? aws_iam_openid_connect_provider.github[0].arn : data.aws_iam_openid_connect_provider.github[0].arn
}

resource "aws_iam_openid_connect_provider" "github" {
  count = var.create_oidc_provider ? 1 : 0

  url             = "https://${local.oidc_issuer}"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = var.oidc_thumbprints

  tags = merge(local.tags, {
    Name = "${var.project}-${var.environment}-github-oidc"
  })
}

data "aws_iam_openid_connect_provider" "github" {
  count = var.create_oidc_provider ? 0 : 1

  url = "https://${local.oidc_issuer}"
}

# ---------------------------------------------------------------------------
# Trust policy
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "assume_role" {
  statement {
    sid    = "GitHubActionsWebIdentity"
    effect = "Allow"

    # Web identity federation only. sts:AssumeRole is deliberately absent — an
    # OIDC token cannot be exchanged through it, and allowing it would open a
    # second, unscoped path into this role.
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_issuer}:aud"
      values   = ["sts.amazonaws.com"]
    }

    # StringEquals, not StringLike: no wildcards in the subject.
    condition {
      test     = "StringEquals"
      variable = "${local.oidc_issuer}:sub"
      values   = [local.allowed_subject]
    }
  }
}

# ---------------------------------------------------------------------------
# Permissions — ECR push only
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "ecr_push" {
  # GetAuthorizationToken is an account-level action: AWS does not support
  # resource scoping for it, so Resource must be "*". It only returns a
  # short-lived registry login token and grants no access on its own.
  statement {
    sid       = "EcrGetAuthorizationToken"
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  # Everything else is scoped to the 8 petclinic repositories.
  statement {
    sid    = "EcrPushToPetclinicRepositories"
    effect = "Allow"

    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
      "ecr:PutImage",
      # Read-back actions: buildx pulls existing layers for cache reuse and
      # Trivy pulls the manifest to scan it.
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer",
      "ecr:DescribeImages",
      "ecr:DescribeRepositories",
    ]

    resources = var.ecr_repository_arns
  }
}

resource "aws_iam_role" "github_actions" {
  name                 = var.role_name
  description          = "GitHub Actions CI role for ${var.github_owner}/${var.app_repository} (${var.allowed_branch}) - ECR push only"
  assume_role_policy   = data.aws_iam_policy_document.assume_role.json
  max_session_duration = 3600

  tags = merge(local.tags, {
    Name = var.role_name
  })
}

resource "aws_iam_policy" "ecr_push" {
  name        = "${var.role_name}-ecr-push"
  description = "Least-privilege ECR push permissions for the petclinic CI pipeline"
  policy      = data.aws_iam_policy_document.ecr_push.json

  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "ecr_push" {
  role       = aws_iam_role.github_actions.name
  policy_arn = aws_iam_policy.ecr_push.arn
}
