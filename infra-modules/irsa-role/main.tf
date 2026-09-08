# =============================================================================
# Generic IRSA role.
#
# Creates an IAM role that a specific set of Kubernetes ServiceAccounts - and
# nothing else - may assume via sts:AssumeRoleWithWebIdentity against the
# cluster's OIDC provider.
#
# The trust policy pins BOTH claims:
#
#   <issuer>:aud  must be one of var.token_audiences
#   <issuer>:sub  must equal system:serviceaccount:<namespace>:<name>
#
# Note the audience is NOT sts.amazonaws.com here. That is the EKS convention;
# kOps runs its pod-identity-webhook with --token-audience=amazonaws.com, so
# every projected token in this cluster carries "amazonaws.com". Pinning the
# EKS value instead produces tokens STS refuses with
# "InvalidIdentityToken: The web identity token provided could not be
# validated" - an error naming neither the audience nor the claim.
#
# Pinning `sub` is what makes this least-privilege. A trust policy that checks
# only `aud` would let ANY ServiceAccount in the cluster assume the role, which
# is a common and serious IRSA misconfiguration - it silently turns a scoped
# role into a cluster-wide one.
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

locals {
  # system:serviceaccount:<namespace>:<name> for every permitted subject.
  subjects = [
    for sa in var.service_accounts :
    "system:serviceaccount:${sa.namespace}:${sa.name}"
  ]

  common_tags = merge(var.tags, {
    ManagedBy = "terraform"
    Module    = "infra-modules/irsa-role"
    IRSA      = "true"
  })
}

data "aws_iam_policy_document" "assume" {
  statement {
    sid     = "AllowScopedServiceAccountsWebIdentity"
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.oidc_issuer_hostname}:aud"
      values   = var.token_audiences
    }

    condition {
      test     = "StringEquals"
      variable = "${var.oidc_issuer_hostname}:sub"
      values   = local.subjects
    }
  }
}

resource "aws_iam_role" "this" {
  name                 = var.role_name
  description          = var.description
  assume_role_policy   = data.aws_iam_policy_document.assume.json
  max_session_duration = var.max_session_duration

  # Defence in depth: even if an attached policy is over-broad, the boundary
  # caps what the role can ever do.
  permissions_boundary = var.permissions_boundary_arn

  tags = merge(local.common_tags, {
    Name = var.role_name
  })
}

# NOTE ON THE count EXPRESSIONS
#
# These are driven by explicit booleans rather than by `policy_json == null`,
# which is the obvious formulation but does not work here. The policy documents
# reference resources created in the same apply (the KMS key, the Route53 zone),
# so their values are unknown at plan time; deriving `count` from them fails
# with "The count value depends on resource attributes that cannot be determined
# until apply". A static boolean keeps the resource graph knowable at plan time.

# Inline policy: used where the permissions are specific to this role and there
# is no value in a standalone reusable policy object.
resource "aws_iam_role_policy" "inline" {
  count = var.create_inline_policy ? 1 : 0

  name   = "${var.role_name}-inline"
  role   = aws_iam_role.this.id
  policy = var.inline_policy_json
}

# Customer-managed policy: a first-class, reusable, separately auditable object.
# The brief asks for "managed policies" for the add-ons, which is what this
# produces.
resource "aws_iam_policy" "managed" {
  count = var.create_managed_policy ? 1 : 0

  name        = "${var.role_name}-policy"
  description = "Managed policy for ${var.role_name}"
  policy      = var.policy_json

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "managed" {
  count = var.create_managed_policy ? 1 : 0

  role       = aws_iam_role.this.name
  policy_arn = aws_iam_policy.managed[0].arn
}

resource "aws_iam_role_policy_attachment" "extra" {
  for_each = toset(var.additional_policy_arns)

  role       = aws_iam_role.this.name
  policy_arn = each.value
}
