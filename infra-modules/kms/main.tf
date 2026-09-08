# =============================================================================
# Customer-managed KMS key for the platform.
#
# Used for:
#   - kOps etcd EBS volume encryption (etcdMembers[].kmsKeyId)
#   - worker/control-plane root volume encryption
#   - Kubernetes Secret envelope encryption at rest
#   - AWS Secrets Manager entries consumed via External Secrets Operator
#
# A customer-managed key rather than the AWS-managed default because the brief
# requires a CMK, and because only a CMK lets us grant cross-service access and
# enable annual rotation on our own terms.
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

  common_tags = merge(var.tags, {
    ManagedBy = "terraform"
    Module    = "infra-modules/kms"
  })
}

data "aws_iam_policy_document" "key" {
  # ---------------------------------------------------------------------------
  # Account root retains full control.
  #
  # This statement is mandatory. Omitting it produces a key that nobody -
  # including an administrator - can manage, and KMS keys cannot be force-
  # deleted; you would wait out the 7-30 day deletion window.
  # ---------------------------------------------------------------------------
  statement {
    sid    = "EnableIAMUserPermissions"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = ["arn:${local.partition}:iam::${local.account_id}:root"]
    }

    actions   = ["kms:*"]
    resources = ["*"]
  }

  # ---------------------------------------------------------------------------
  # Autoscaling needs to use the key on the cluster's behalf, otherwise
  # instances with encrypted root volumes fail to launch with an opaque
  # "Client.InternalError: Client error on launch".
  # ---------------------------------------------------------------------------
  dynamic "statement" {
    for_each = var.allow_autoscaling_service_linked_role ? [1] : []

    content {
      sid    = "AllowAutoScalingServiceLinkedRole"
      effect = "Allow"

      principals {
        type = "AWS"
        identifiers = [
          "arn:${local.partition}:iam::${local.account_id}:role/aws-service-role/autoscaling.amazonaws.com/AWSServiceRoleForAutoScaling"
        ]
      }

      actions = [
        "kms:Encrypt",
        "kms:Decrypt",
        "kms:ReEncrypt*",
        "kms:GenerateDataKey*",
        "kms:DescribeKey",
        "kms:CreateGrant",
      ]

      resources = ["*"]
    }
  }

  # ---------------------------------------------------------------------------
  # Additional principals (node roles, IRSA roles) granted data-plane use.
  # ---------------------------------------------------------------------------
  dynamic "statement" {
    for_each = length(var.key_users) > 0 ? [1] : []

    content {
      sid    = "AllowKeyUsage"
      effect = "Allow"

      principals {
        type        = "AWS"
        identifiers = var.key_users
      }

      actions = [
        "kms:Encrypt",
        "kms:Decrypt",
        "kms:ReEncrypt*",
        "kms:GenerateDataKey*",
        "kms:DescribeKey",
      ]

      resources = ["*"]
    }
  }

  dynamic "statement" {
    for_each = length(var.key_users) > 0 ? [1] : []

    content {
      sid    = "AllowAttachmentOfPersistentResources"
      effect = "Allow"

      principals {
        type        = "AWS"
        identifiers = var.key_users
      }

      actions = [
        "kms:CreateGrant",
        "kms:ListGrants",
        "kms:RevokeGrant",
      ]

      resources = ["*"]

      # Restrict grants to AWS services that attach persistent resources
      # (EBS, ASG) rather than allowing arbitrary grant creation.
      condition {
        test     = "Bool"
        variable = "kms:GrantIsForAWSResource"
        values   = ["true"]
      }
    }
  }
}

resource "aws_kms_key" "this" {
  description = var.description

  # Rotation is cheap and is a baseline expectation for any key protecting
  # data at rest.
  enable_key_rotation = true

  # A short window in a throwaway environment; production would use 30.
  deletion_window_in_days = var.deletion_window_in_days

  policy = data.aws_iam_policy_document.key.json

  tags = merge(local.common_tags, {
    Name = var.alias_name
  })
}

resource "aws_kms_alias" "this" {
  name          = "alias/${var.alias_name}"
  target_key_id = aws_kms_key.this.key_id
}
