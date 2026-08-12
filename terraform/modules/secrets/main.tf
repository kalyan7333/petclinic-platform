locals {
  name = "${var.project}-${var.environment}"
  tags = merge(var.tags, { Component = "secrets" })

  # Secrets Manager ARNs carry a 6-character random suffix, so policies must use a
  # wildcard. Scoped to this environment's secret prefix rather than the whole
  # petclinic/* namespace so the dev role cannot read prod secrets.
  secret_arn_pattern = "arn:${data.aws_partition.current.partition}:secretsmanager:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:secret:${var.project}/${var.environment}/*"
}

data "aws_partition" "current" {}

data "aws_region" "current" {}

data "aws_caller_identity" "current" {}

# ---- Application secrets (non-RDS) ----
# RDS credentials are owned by the RDS module (PETPLAT-23) — never duplicated here.

# OpenAI API key — used by genai-service
resource "aws_secretsmanager_secret" "openai" {
  name                    = "${var.project}/${var.environment}/openai-api-key"
  description             = "OpenAI API key for genai-service (${var.environment})"
  recovery_window_in_days = var.secret_recovery_window_in_days
  tags                    = local.tags
}

resource "aws_secretsmanager_secret_version" "openai" {
  count         = var.openai_api_key != "" ? 1 : 0
  secret_id     = aws_secretsmanager_secret.openai.id
  secret_string = var.openai_api_key
}

# Optional: credentials for a private Git repo backing the Config Server.
# Created only when create_config_server_git_credentials = true. The secret
# versions are written only when values are supplied, so the secrets can be
# provisioned first and populated out of band.
resource "aws_secretsmanager_secret" "config_server_git_username" {
  count                   = var.create_config_server_git_credentials ? 1 : 0
  name                    = "${var.project}/${var.environment}/config-server/git-username"
  description             = "Git username for the Config Server backing repository (${var.environment})"
  recovery_window_in_days = var.secret_recovery_window_in_days
  tags                    = local.tags
}

resource "aws_secretsmanager_secret_version" "config_server_git_username" {
  count         = var.create_config_server_git_credentials && var.config_server_git_username != "" ? 1 : 0
  secret_id     = aws_secretsmanager_secret.config_server_git_username[0].id
  secret_string = var.config_server_git_username
}

resource "aws_secretsmanager_secret" "config_server_git_password" {
  count                   = var.create_config_server_git_credentials ? 1 : 0
  name                    = "${var.project}/${var.environment}/config-server/git-password"
  description             = "Git password/token for the Config Server backing repository (${var.environment})"
  recovery_window_in_days = var.secret_recovery_window_in_days
  tags                    = local.tags
}

resource "aws_secretsmanager_secret_version" "config_server_git_password" {
  count         = var.create_config_server_git_credentials && var.config_server_git_password != "" ? 1 : 0
  secret_id     = aws_secretsmanager_secret.config_server_git_password[0].id
  secret_string = var.config_server_git_password
}

# ---- External Secrets Operator IRSA role (PETPLAT-37) ----

data "aws_iam_policy_document" "eso_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.oidc_provider_url}:sub"
      values   = ["system:serviceaccount:${var.eso_namespace}:${var.eso_service_account}"]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.oidc_provider_url}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "eso" {
  statement {
    sid    = "ReadPetclinicSecrets"
    effect = "Allow"

    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret",
    ]

    resources = [local.secret_arn_pattern]
  }

  # Only needed when secrets are encrypted with a customer-managed KMS key. The
  # default aws/secretsmanager key is decrypted through the Secrets Manager
  # service principal and needs no explicit grant.
  dynamic "statement" {
    for_each = length(var.kms_key_arns) > 0 ? [1] : []

    content {
      sid       = "DecryptCustomerManagedKeys"
      effect    = "Allow"
      actions   = ["kms:Decrypt"]
      resources = var.kms_key_arns
    }
  }
}

resource "aws_iam_policy" "eso" {
  name        = "${local.name}-eso-policy"
  description = "Secrets Manager read access for the External Secrets Operator on ${local.name}"
  policy      = data.aws_iam_policy_document.eso.json

  tags = local.tags
}

resource "aws_iam_role" "eso" {
  name               = "${local.name}-eso-role"
  description        = "IRSA role for the External Secrets Operator service account (${var.eso_namespace}/${var.eso_service_account})"
  assume_role_policy = data.aws_iam_policy_document.eso_assume_role.json

  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "eso" {
  role       = aws_iam_role.eso.name
  policy_arn = aws_iam_policy.eso.arn
}
