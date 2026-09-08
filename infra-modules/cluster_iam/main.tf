# =============================================================================
# Additional IAM permissions for the kOps node and control-plane instance
# profiles.
#
# kOps creates the instance profiles and their baseline policies itself - that
# is not something Terraform should duplicate or fight over. What this module
# provides is the *extra* policy documents that get injected into the cluster
# spec's `spec.additionalPolicies` block, plus the account-level guardrails
# that belong to Terraform.
#
# Consequently this module mostly emits JSON rather than creating IAM objects.
# The kOps cluster template renders these strings straight into the manifest.
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
}

# -----------------------------------------------------------------------------
# Worker nodes
# -----------------------------------------------------------------------------

data "aws_iam_policy_document" "node" {
  # SSM Session Manager. This is a deliberate operability choice: it gives
  # break-glass shell access to a private node without opening SSH, without a
  # key pair, and with every session logged in CloudTrail. The bastion remains
  # for kubectl/DNS tunnelling; SSM is for when a node itself is unhealthy.
  statement {
    sid    = "SsmSessionManager"
    effect = "Allow"
    actions = [
      "ssm:UpdateInstanceInformation",
      "ssm:ListAssociations",
      "ssm:ListInstanceAssociations",
      "ssmmessages:CreateControlChannel",
      "ssmmessages:CreateDataChannel",
      "ssmmessages:OpenControlChannel",
      "ssmmessages:OpenDataChannel",
      "ec2messages:AcknowledgeMessage",
      "ec2messages:DeleteMessage",
      "ec2messages:FailMessage",
      "ec2messages:GetEndpoint",
      "ec2messages:GetMessages",
      "ec2messages:SendReply",
    ]
    resources = ["*"]
  }

  # The kubelet and several DaemonSets read instance tags to discover the
  # cluster name and node role.
  statement {
    sid       = "DescribeTags"
    effect    = "Allow"
    actions   = ["ec2:DescribeTags", "ec2:DescribeInstances"]
    resources = ["*"]
  }

  # Nodes must decrypt their own KMS-encrypted root and etcd volumes.
  statement {
    sid    = "UsePlatformKey"
    effect = "Allow"
    actions = [
      "kms:Decrypt",
      "kms:DescribeKey",
      "kms:GenerateDataKeyWithoutPlaintext",
    ]
    resources = [var.kms_key_arn]
  }

  # Read-only access to the public OIDC discovery bucket. Nodes fetch the JWKS
  # when validating projected service account tokens.
  statement {
    sid       = "ReadOidcDiscovery"
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = ["${var.oidc_bucket_arn}/*"]
  }
}

# -----------------------------------------------------------------------------
# Control plane
# -----------------------------------------------------------------------------

data "aws_iam_policy_document" "control_plane" {
  statement {
    sid    = "SsmSessionManager"
    effect = "Allow"
    actions = [
      "ssm:UpdateInstanceInformation",
      "ssmmessages:CreateControlChannel",
      "ssmmessages:CreateDataChannel",
      "ssmmessages:OpenControlChannel",
      "ssmmessages:OpenDataChannel",
      "ec2messages:AcknowledgeMessage",
      "ec2messages:DeleteMessage",
      "ec2messages:FailMessage",
      "ec2messages:GetEndpoint",
      "ec2messages:GetMessages",
      "ec2messages:SendReply",
    ]
    resources = ["*"]
  }

  # etcd-manager attaches, detaches and snapshots the etcd data volumes, all of
  # which are CMK-encrypted.
  statement {
    sid    = "EtcdVolumeEncryption"
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
    sid       = "CreateGrantForEtcdVolumes"
    effect    = "Allow"
    actions   = ["kms:CreateGrant"]
    resources = [var.kms_key_arn]

    condition {
      test     = "Bool"
      variable = "kms:GrantIsForAWSResource"
      values   = ["true"]
    }
  }

  # Publishing the OIDC discovery documents on cluster creation and rotation.
  statement {
    sid    = "PublishOidcDiscovery"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:PutObjectAcl",
      "s3:ListBucket",
    ]
    resources = [
      var.oidc_bucket_arn,
      "${var.oidc_bucket_arn}/*",
    ]
  }
}
