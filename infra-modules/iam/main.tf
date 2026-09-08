# =============================================================================
# IRSA roles and managed policies for the platform add-ons.
#
# Every role here is created by Terraform (not by kOps) and trusts exactly one
# ServiceAccount, so a compromised controller cannot borrow another's
# permissions. Policies are scoped to specific resources wherever the AWS API
# supports it - most notably external-dns and cert-manager, which are pinned to
# the single hosted zone this platform owns rather than being given account-wide
# Route53 write access.
# =============================================================================

terraform {
  required_version = ">= 1.9.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0, < 7.0"
    }
  }
}

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition

  tags = merge(var.tags, {
    ManagedBy = "terraform"
    Module    = "infra-modules/iam"
  })

  irsa_common = {
    oidc_provider_arn    = var.oidc_provider_arn
    oidc_issuer_hostname = var.oidc_issuer_hostname
  }
}

# =============================================================================
# external-dns
# =============================================================================

data "aws_iam_policy_document" "external_dns" {
  # Record mutation is restricted to the one hosted zone we own. Granting
  # ChangeResourceRecordSets on "*" would let a compromised external-dns
  # rewrite DNS for every zone in the account.
  statement {
    sid       = "ChangeRecordsInOwnedZoneOnly"
    effect    = "Allow"
    actions   = ["route53:ChangeResourceRecordSets"]
    resources = [var.route53_zone_arn]
  }

  # Discovery calls do not support resource-level permissions; AWS requires "*".
  statement {
    sid    = "DiscoverZones"
    effect = "Allow"
    actions = [
      "route53:ListHostedZones",
      "route53:ListResourceRecordSets",
      "route53:ListTagsForResource",
      "route53:GetHostedZone",
    ]
    resources = ["*"]
  }
}

module "external_dns" {
  source = "../irsa-role"

  role_name            = "${var.name_prefix}-external-dns"
  description          = "external-dns: manages records in ${var.route53_zone_name}"
  oidc_provider_arn    = local.irsa_common.oidc_provider_arn
  oidc_issuer_hostname = local.irsa_common.oidc_issuer_hostname

  service_accounts = [{
    namespace = "platform-system"
    name      = "external-dns"
  }]

  policy_json = data.aws_iam_policy_document.external_dns.json
  tags        = local.tags
}

# =============================================================================
# cert-manager
#
# Only needed for ACME DNS-01 challenges. In dev the active issuer is a
# self-signed CA (see docs/adr/0002-dns-topology.md), so this role is currently
# unused - but it is provisioned so that switching to a public domain and a real
# ACME issuer is a values change, not an infrastructure change.
# =============================================================================

data "aws_iam_policy_document" "cert_manager" {
  statement {
    sid       = "GetChangeStatus"
    effect    = "Allow"
    actions   = ["route53:GetChange"]
    resources = ["arn:${local.partition}:route53:::change/*"]
  }

  statement {
    sid       = "SolveDns01InOwnedZoneOnly"
    effect    = "Allow"
    actions   = ["route53:ChangeResourceRecordSets", "route53:ListResourceRecordSets"]
    resources = [var.route53_zone_arn]
  }

  statement {
    sid       = "DiscoverZones"
    effect    = "Allow"
    actions   = ["route53:ListHostedZonesByName"]
    resources = ["*"]
  }
}

module "cert_manager" {
  source = "../irsa-role"

  role_name            = "${var.name_prefix}-cert-manager"
  description          = "cert-manager: ACME DNS-01 solver for ${var.route53_zone_name}"
  oidc_provider_arn    = local.irsa_common.oidc_provider_arn
  oidc_issuer_hostname = local.irsa_common.oidc_issuer_hostname

  service_accounts = [{
    namespace = "cert-manager"
    name      = "cert-manager"
  }]

  policy_json = data.aws_iam_policy_document.cert_manager.json
  tags        = local.tags
}

# =============================================================================
# cluster-autoscaler
# =============================================================================

data "aws_iam_policy_document" "cluster_autoscaler" {
  # Read-only discovery across all ASGs: the autoscaler must enumerate groups
  # before it can tell which belong to this cluster.
  statement {
    sid    = "Discovery"
    effect = "Allow"
    actions = [
      "autoscaling:DescribeAutoScalingGroups",
      "autoscaling:DescribeAutoScalingInstances",
      "autoscaling:DescribeLaunchConfigurations",
      "autoscaling:DescribeScalingActivities",
      "autoscaling:DescribeTags",
      "ec2:DescribeImages",
      "ec2:DescribeInstanceTypes",
      "ec2:DescribeLaunchTemplateVersions",
      "ec2:GetInstanceTypesFromInstanceRequirements",
    ]
    resources = ["*"]
  }

  # Mutation is confined to ASGs tagged as belonging to THIS cluster, so the
  # autoscaler cannot resize another cluster's node groups.
  statement {
    sid    = "MutateOwnClusterAsgsOnly"
    effect = "Allow"
    actions = [
      "autoscaling:SetDesiredCapacity",
      "autoscaling:TerminateInstanceInAutoScalingGroup",
      "autoscaling:UpdateAutoScalingGroup",
    ]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "autoscaling:ResourceTag/kubernetes.io/cluster/${var.cluster_name}"
      values   = ["owned"]
    }
  }
}

module "cluster_autoscaler" {
  source = "../irsa-role"

  role_name            = "${var.name_prefix}-cluster-autoscaler"
  description          = "cluster-autoscaler for ${var.cluster_name}"
  oidc_provider_arn    = local.irsa_common.oidc_provider_arn
  oidc_issuer_hostname = local.irsa_common.oidc_issuer_hostname

  service_accounts = [{
    namespace = "kube-system"
    name      = "cluster-autoscaler"
  }]

  policy_json = data.aws_iam_policy_document.cluster_autoscaler.json
  tags        = local.tags
}

# =============================================================================
# AWS Load Balancer Controller
#
# Uses the upstream policy document verbatim (vendored at
# policies/aws-load-balancer-controller.json, pinned to controller v2.13.4)
# rather than a hand-written approximation. This policy is large and subtle -
# hand-trimming it is a well-known source of controllers that appear healthy
# but fail to reconcile a TargetGroupBinding hours later.
# =============================================================================

module "aws_load_balancer_controller" {
  source = "../irsa-role"

  role_name            = "${var.name_prefix}-aws-lbc"
  description          = "AWS Load Balancer Controller for ${var.cluster_name}"
  oidc_provider_arn    = local.irsa_common.oidc_provider_arn
  oidc_issuer_hostname = local.irsa_common.oidc_issuer_hostname

  service_accounts = [{
    namespace = "kube-system"
    name      = "aws-load-balancer-controller"
  }]

  policy_json = file("${path.module}/policies/aws-load-balancer-controller.json")
  tags        = local.tags
}

# =============================================================================
# External Secrets Operator
# =============================================================================

data "aws_iam_policy_document" "external_secrets" {
  statement {
    sid    = "ReadPlatformSecrets"
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret",
    ]
    # Scoped by name prefix so the operator can only read secrets belonging to
    # this platform, not every secret in the account.
    resources = [
      "arn:${local.partition}:secretsmanager:${var.region}:${local.account_id}:secret:${var.secret_name_prefix}/*",
    ]
  }

  statement {
    sid       = "ListSecrets"
    effect    = "Allow"
    actions   = ["secretsmanager:ListSecrets"]
    resources = ["*"]
  }

  statement {
    sid    = "ReadPlatformParameters"
    effect = "Allow"
    actions = [
      "ssm:GetParameter",
      "ssm:GetParameters",
      "ssm:GetParametersByPath",
      "ssm:DescribeParameters",
    ]
    resources = [
      "arn:${local.partition}:ssm:${var.region}:${local.account_id}:parameter/${var.secret_name_prefix}/*",
    ]
  }

  # Secrets Manager entries are envelope-encrypted with the platform CMK, so
  # the operator needs Decrypt on that key specifically.
  statement {
    sid       = "DecryptWithPlatformKey"
    effect    = "Allow"
    actions   = ["kms:Decrypt", "kms:DescribeKey"]
    resources = [var.kms_key_arn]
  }
}

module "external_secrets" {
  source = "../irsa-role"

  role_name            = "${var.name_prefix}-external-secrets"
  description          = "External Secrets Operator for ${var.cluster_name}"
  oidc_provider_arn    = local.irsa_common.oidc_provider_arn
  oidc_issuer_hostname = local.irsa_common.oidc_issuer_hostname

  service_accounts = [{
    namespace = "platform-system"
    name      = "external-secrets"
  }]

  policy_json = data.aws_iam_policy_document.external_secrets.json
  tags        = local.tags
}

# =============================================================================
# EBS CSI driver
#
# Uses the AWS-managed policy: it is maintained by AWS and tracks new EBS
# features automatically, which is preferable to vendoring a copy that silently
# goes stale.
# =============================================================================

module "ebs_csi" {
  source = "../irsa-role"

  role_name            = "${var.name_prefix}-ebs-csi"
  description          = "EBS CSI driver controller for ${var.cluster_name}"
  oidc_provider_arn    = local.irsa_common.oidc_provider_arn
  oidc_issuer_hostname = local.irsa_common.oidc_issuer_hostname

  service_accounts = [{
    namespace = "kube-system"
    name      = "ebs-csi-controller-sa"
  }]

  additional_policy_arns = [
    "arn:${local.partition}:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
  ]

  # No customer-managed policy of its own - the AWS-managed one above covers
  # the EBS API surface.
  create_managed_policy = false

  # The managed policy omits KMS, so encrypted volumes need this added
  # explicitly - without it, PVC provisioning fails with a KMS AccessDenied
  # that surfaces only in the CSI controller logs.
  create_inline_policy = true
  inline_policy_json   = data.aws_iam_policy_document.ebs_csi_kms.json

  tags = local.tags
}

data "aws_iam_policy_document" "ebs_csi_kms" {
  statement {
    sid    = "UsePlatformKeyForVolumes"
    effect = "Allow"
    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:DescribeKey",
    ]
    resources = [var.kms_key_arn]
  }

  statement {
    sid       = "CreateGrantForAttachedVolumes"
    effect    = "Allow"
    actions   = ["kms:CreateGrant"]
    resources = [var.kms_key_arn]

    condition {
      test     = "Bool"
      variable = "kms:GrantIsForAWSResource"
      values   = ["true"]
    }
  }
}
