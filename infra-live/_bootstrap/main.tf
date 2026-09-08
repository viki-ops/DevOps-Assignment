# =============================================================================
# Bootstrap stack: creates the Terraform state bucket and DynamoDB lock table
# that every other stack in infra-live depends on, plus the kOps state store.
#
# THE CHICKEN-AND-EGG
# -------------------
# This stack creates the bucket it will itself be stored in, so it cannot use
# that bucket as a backend on the very first apply. The sequence is:
#
#   1. terraform init && terraform apply   (state is local)
#   2. terraform init -migrate-state       (state moves into the new bucket)
#
# `make bootstrap` performs both steps. After migration the real state lives in
# S3 like everything else, so there is no untracked local state to lose.
#
# WHY NEW BUCKETS IN eu-north-1
# -----------------------------
# The account already contained platform-tfstate-125788629837 and
# platform-dev-kops-state-125788629837, both empty and both in us-west-2. They
# are deliberately NOT reused. The platform runs in eu-north-1, and a kOps state
# store in another region means every node fetches its configuration
# cross-region on boot, bypassing the S3 gateway VPC endpoint and paying NAT
# egress for it. Keeping state co-located with the cluster avoids that.
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

provider "aws" {
  region = var.region

  default_tags {
    tags = local.default_tags
  }
}

locals {
  default_tags = {
    Project     = var.project
    Environment = "shared"
    ManagedBy   = "terraform"
    Stack       = "infra-live/_bootstrap"
    Owner       = var.owner
  }
}

data "aws_caller_identity" "current" {}

module "state_backend" {
  source = "../../infra-modules/s3_backend"

  bucket_name     = var.state_bucket_name
  lock_table_name = var.lock_table_name

  # SSE-S3 rather than a CMK: the KMS key is created by the dev stack, which
  # stores its state here. A CMK dependency would invert that ordering.
  kms_key_arn = null

  tags = local.default_tags
}

# -----------------------------------------------------------------------------
# kOps state store
#
# Lives in the bootstrap stack rather than the dev stack on purpose: a
# `terraform destroy` of dev must not delete the bucket that describes a cluster
# which may still be running. Its lifecycle is deliberately decoupled.
# -----------------------------------------------------------------------------

resource "aws_s3_bucket" "kops_state" {
  bucket        = var.kops_state_bucket_name
  force_destroy = false

  tags = merge(local.default_tags, {
    Name    = var.kops_state_bucket_name
    Purpose = "kops-cluster-state"
  })
}

# kOps keeps the full cluster spec and all PKI here. Versioning is the recovery
# path if a bad `kops replace` corrupts the spec.
resource "aws_s3_bucket_versioning" "kops_state" {
  bucket = aws_s3_bucket.kops_state.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "kops_state" {
  bucket = aws_s3_bucket.kops_state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# This bucket holds the cluster CA private keys. It must never be public.
resource "aws_s3_bucket_public_access_block" "kops_state" {
  bucket = aws_s3_bucket.kops_state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "kops_state" {
  bucket = aws_s3_bucket.kops_state.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

data "aws_iam_policy_document" "kops_state" {
  statement {
    sid    = "DenyInsecureTransport"
    effect = "Deny"

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    actions = ["s3:*"]

    resources = [
      aws_s3_bucket.kops_state.arn,
      "${aws_s3_bucket.kops_state.arn}/*",
    ]

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "kops_state" {
  bucket = aws_s3_bucket.kops_state.id
  policy = data.aws_iam_policy_document.kops_state.json

  depends_on = [aws_s3_bucket_public_access_block.kops_state]
}
