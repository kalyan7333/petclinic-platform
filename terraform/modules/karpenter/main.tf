locals {
  name = "${var.project}-${var.environment}"
  tags = merge(var.tags, { Component = "karpenter" })
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# ---- SQS Interruption Queue ----

resource "aws_sqs_queue" "karpenter_interruption" {
  name                      = "${local.name}-karpenter-interruption"
  message_retention_seconds = 300
  sqs_managed_sse_enabled   = true

  tags = local.tags
}

resource "aws_sqs_queue_policy" "karpenter_interruption" {
  queue_url = aws_sqs_queue.karpenter_interruption.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = ["events.amazonaws.com", "sqs.amazonaws.com"] }
        Action    = "sqs:SendMessage"
        Resource  = aws_sqs_queue.karpenter_interruption.arn
      }
    ]
  })
}

# ---- EventBridge Rules for Spot Interruption Handling ----

resource "aws_cloudwatch_event_rule" "spot_interruption" {
  name        = "${local.name}-spot-interruption"
  description = "Karpenter: EC2 Spot Instance Interruption Warning"
  event_pattern = jsonencode({
    source      = ["aws.ec2"]
    detail-type = ["EC2 Spot Instance Interruption Warning"]
  })
  tags = local.tags
}

resource "aws_cloudwatch_event_target" "spot_interruption" {
  rule      = aws_cloudwatch_event_rule.spot_interruption.name
  target_id = "KarpenterInterruptionQueue"
  arn       = aws_sqs_queue.karpenter_interruption.arn
}

resource "aws_cloudwatch_event_rule" "rebalance" {
  name        = "${local.name}-rebalance"
  description = "Karpenter: EC2 Instance Rebalance Recommendation"
  event_pattern = jsonencode({
    source      = ["aws.ec2"]
    detail-type = ["EC2 Instance Rebalance Recommendation"]
  })
  tags = local.tags
}

resource "aws_cloudwatch_event_target" "rebalance" {
  rule      = aws_cloudwatch_event_rule.rebalance.name
  target_id = "KarpenterInterruptionQueue"
  arn       = aws_sqs_queue.karpenter_interruption.arn
}

resource "aws_cloudwatch_event_rule" "instance_state_change" {
  name        = "${local.name}-instance-state-change"
  description = "Karpenter: EC2 Instance State Change"
  event_pattern = jsonencode({
    source      = ["aws.ec2"]
    detail-type = ["EC2 Instance State-change Notification"]
  })
  tags = local.tags
}

resource "aws_cloudwatch_event_target" "instance_state_change" {
  rule      = aws_cloudwatch_event_rule.instance_state_change.name
  target_id = "KarpenterInterruptionQueue"
  arn       = aws_sqs_queue.karpenter_interruption.arn
}

# ---- Karpenter Instance Profile ----

resource "aws_iam_instance_profile" "karpenter_node" {
  name = "${local.name}-karpenter-node-profile"
  role = var.node_role_name
  tags = local.tags
}

# ---- IRSA Role for Karpenter Controller ----

resource "aws_iam_role" "karpenter_controller" {
  name = "${local.name}-karpenter-controller"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = var.oidc_provider_arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${var.oidc_provider_url}:sub" = "system:serviceaccount:kube-system:karpenter"
          "${var.oidc_provider_url}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })

  tags = local.tags
}

resource "aws_iam_policy" "karpenter_controller" {
  name        = "${local.name}-karpenter-controller-policy"
  description = "Policy for Karpenter node provisioner"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowScopedEC2InstanceActions"
        Effect = "Allow"
        Resource = [
          "arn:aws:ec2:${data.aws_region.current.name}::image/*",
          "arn:aws:ec2:${data.aws_region.current.name}::snapshot/*",
          "arn:aws:ec2:${data.aws_region.current.name}:*:spot-instances-request/*",
          "arn:aws:ec2:${data.aws_region.current.name}:*:security-group/*",
          "arn:aws:ec2:${data.aws_region.current.name}:*:subnet/*",
          "arn:aws:ec2:${data.aws_region.current.name}:*:launch-template/*",
        ]
        Action = ["ec2:RunInstances", "ec2:CreateFleet"]
      },
      {
        Sid      = "AllowScopedEC2InstanceActionsWithTags"
        Effect   = "Allow"
        Resource = ["arn:aws:ec2:${data.aws_region.current.name}:*:instance/*", "arn:aws:ec2:${data.aws_region.current.name}:*:volume/*", "arn:aws:ec2:${data.aws_region.current.name}:*:network-interface/*"]
        Action   = ["ec2:RunInstances", "ec2:CreateFleet", "ec2:CreateLaunchTemplate"]
        Condition = {
          StringEquals = { "aws:RequestTag/kubernetes.io/cluster/${var.cluster_name}" = "owned" }
        }
      },
      {
        Sid      = "AllowScopedResourceCreationTagging"
        Effect   = "Allow"
        Resource = ["arn:aws:ec2:${data.aws_region.current.name}:*:instance/*", "arn:aws:ec2:${data.aws_region.current.name}:*:volume/*", "arn:aws:ec2:${data.aws_region.current.name}:*:network-interface/*", "arn:aws:ec2:${data.aws_region.current.name}:*:launch-template/*", "arn:aws:ec2:${data.aws_region.current.name}:*:spot-instances-request/*"]
        Action   = ["ec2:CreateTags"]
        Condition = {
          StringEquals = { "ec2:CreateAction" = ["RunInstances", "CreateFleet", "CreateLaunchTemplate"] }
        }
      },
      {
        Sid      = "AllowScopedDeletion"
        Effect   = "Allow"
        Resource = ["arn:aws:ec2:${data.aws_region.current.name}:*:instance/*", "arn:aws:ec2:${data.aws_region.current.name}:*:launch-template/*"]
        Action   = ["ec2:TerminateInstances", "ec2:DeleteLaunchTemplate"]
        Condition = {
          StringEquals = { "aws:ResourceTag/kubernetes.io/cluster/${var.cluster_name}" = "owned" }
        }
      },
      {
        Sid      = "AllowRegionalReadActions"
        Effect   = "Allow"
        Resource = "*"
        Action   = ["ec2:DescribeAvailabilityZones", "ec2:DescribeImages", "ec2:DescribeInstances", "ec2:DescribeInstanceTypeOfferings", "ec2:DescribeInstanceTypes", "ec2:DescribeLaunchTemplates", "ec2:DescribeSecurityGroups", "ec2:DescribeSpotPriceHistory", "ec2:DescribeSubnets"]
      },
      {
        Sid      = "AllowSSMReadActions"
        Effect   = "Allow"
        Resource = "arn:aws:ssm:${data.aws_region.current.name}::parameter/aws/service/*"
        Action   = ["ssm:GetParameter"]
      },
      {
        Sid      = "AllowPricingReadActions"
        Effect   = "Allow"
        Resource = "*"
        Action   = ["pricing:GetProducts"]
      },
      {
        Sid      = "AllowInterruptionQueueActions"
        Effect   = "Allow"
        Resource = aws_sqs_queue.karpenter_interruption.arn
        Action   = ["sqs:DeleteMessage", "sqs:GetQueueAttributes", "sqs:GetQueueUrl", "sqs:ReceiveMessage"]
      },
      {
        Sid      = "AllowPassingInstanceRole"
        Effect   = "Allow"
        Resource = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${var.node_role_name}"
        Action   = ["iam:PassRole"]
      },
      {
        Sid      = "AllowScopedInstanceProfileCreationActions"
        Effect   = "Allow"
        Resource = "*"
        Action   = ["iam:CreateInstanceProfile"]
        Condition = {
          StringEquals = { "aws:RequestTag/kubernetes.io/cluster/${var.cluster_name}" = "owned" }
        }
      },
      {
        Sid      = "AllowScopedInstanceProfileTagActions"
        Effect   = "Allow"
        Resource = "*"
        Action   = ["iam:TagInstanceProfile"]
        Condition = {
          StringEquals = { "aws:ResourceTag/kubernetes.io/cluster/${var.cluster_name}" = "owned" }
        }
      },
      {
        Sid      = "AllowScopedInstanceProfileActions"
        Effect   = "Allow"
        Resource = "*"
        Action   = ["iam:AddRoleToInstanceProfile", "iam:RemoveRoleFromInstanceProfile", "iam:DeleteInstanceProfile"]
        Condition = {
          StringEquals = { "aws:ResourceTag/kubernetes.io/cluster/${var.cluster_name}" = "owned" }
        }
      },
      {
        Sid      = "AllowInstanceProfileReadActions"
        Effect   = "Allow"
        Resource = "*"
        Action   = ["iam:GetInstanceProfile"]
      },
      {
        Sid      = "AllowAPIServerEndpointDiscovery"
        Effect   = "Allow"
        Resource = "arn:aws:eks:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:cluster/${var.cluster_name}"
        Action   = ["eks:DescribeCluster"]
      },
    ]
  })

  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "karpenter_controller" {
  role       = aws_iam_role.karpenter_controller.name
  policy_arn = aws_iam_policy.karpenter_controller.arn
}
