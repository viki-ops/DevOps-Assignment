# =============================================================================
# IRSA role for ArgoCD.
#
# ArgoCD itself does not need AWS credentials to do GitOps against a public
# GitHub repository. This role exists for the things around that:
#
#   - repo-server pulling Helm charts from ECR (OCI registries)
#   - repo-server reading repository credentials out of Secrets Manager
#     instead of holding them in a long-lived Kubernetes Secret
#   - the application-controller decrypting values with the platform CMK
#
# Kept in its own module (rather than folded into infra-modules/iam) because
# the brief lists argocd-iam as a distinct module, and because ArgoCD's
# lifecycle is independent of the cluster add-ons.
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
    Module    = "infra-modules/argocd-iam"
    Component = "argocd"
  })
}

data "aws_iam_policy_document" "repo_server" {
  # ECR authentication is account-wide by API design: GetAuthorizationToken
  # does not accept a resource scope.
  statement {
    sid       = "EcrAuth"
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid    = "EcrPullCharts"
    effect = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:DescribeImages",
      "ecr:DescribeRepositories",
      "ecr:GetDownloadUrlForLayer",
      "ecr:ListImages",
    ]
    resources = [
      "arn:${local.partition}:ecr:${var.region}:${local.account_id}:repository/*",
    ]
  }

  # Public ECR (the retail-store sample images live here) uses a separate
  # service principal and only supports account-wide auth tokens.
  statement {
    sid       = "EcrPublicAuth"
    effect    = "Allow"
    actions   = ["ecr-public:GetAuthorizationToken", "sts:GetServiceBearerToken"]
    resources = ["*"]
  }

  statement {
    sid    = "ReadArgoCdSecrets"
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret",
    ]
    resources = [
      "arn:${local.partition}:secretsmanager:${var.region}:${local.account_id}:secret:${var.secret_name_prefix}/argocd/*",
    ]
  }

  statement {
    sid       = "DecryptWithPlatformKey"
    effect    = "Allow"
    actions   = ["kms:Decrypt", "kms:DescribeKey"]
    resources = [var.kms_key_arn]
  }
}

module "repo_server" {
  source = "../irsa-role"

  role_name            = "${var.name_prefix}-argocd-repo-server"
  description          = "ArgoCD repo-server: pulls OCI charts from ECR and repository credentials from Secrets Manager"
  oidc_provider_arn    = var.oidc_provider_arn
  oidc_issuer_hostname = var.oidc_issuer_hostname

  # Both the repo-server and the application-controller resolve chart sources,
  # so both are trusted subjects on this one role rather than duplicating it.
  service_accounts = [
    {
      namespace = var.argocd_namespace
      name      = "argocd-repo-server"
    },
    {
      namespace = var.argocd_namespace
      name      = "argocd-application-controller"
    },
  ]

  policy_json = data.aws_iam_policy_document.repo_server.json
  tags        = local.tags
}
