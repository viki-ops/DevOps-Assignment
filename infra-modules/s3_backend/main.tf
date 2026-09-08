# =============================================================================
# Terraform remote state backend: versioned, encrypted S3 bucket plus a
# DynamoDB table for state locking.
#
# Bootstrap ordering note: this module creates the bucket that every other
# stack stores its state in, so it cannot itself use that bucket as a backend
# on the first apply. It is consumed by infra-live/_bootstrap, which starts
# with local state and then migrates its own state into the bucket it just
# created. See infra-live/_bootstrap/README.md.
#
# DynamoDB locking is used because the brief explicitly asks for it. Terraform
# 1.10+ also supports native S3 locking via `use_lockfile`, which removes the
# DynamoDB dependency entirely; that is noted in the README as the modern
# alternative.
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
  common_tags = merge(var.tags, {
    ManagedBy = "terraform"
    Module    = "infra-modules/s3_backend"
    Purpose   = "terraform-remote-state"
  })
}

# -----------------------------------------------------------------------------
# State bucket
# -----------------------------------------------------------------------------

resource "aws_s3_bucket" "state" {
  bucket = var.bucket_name

  # State buckets must survive `terraform destroy` of the stacks that use them.
  # Deleting this bucket would orphan every managed resource in the account.
  force_destroy = false

  tags = merge(local.common_tags, {
    Name = var.bucket_name
  })

  lifecycle {
    prevent_destroy = true
  }
}

# Versioning is the single most important setting here: it is the only way to
# recover from a corrupted or truncated state push.
resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = var.kms_key_arn == null ? "AES256" : "aws:kms"
      kms_master_key_id = var.kms_key_arn
    }

    # Cuts KMS request costs substantially on buckets with many small objects.
    bucket_key_enabled = var.kms_key_arn != null
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket = aws_s3_bucket.state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

# Expire non-current state versions so the bucket does not grow without bound,
# while retaining enough history to recover from a bad apply.
resource "aws_s3_bucket_lifecycle_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    id     = "expire-noncurrent-state-versions"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days           = var.noncurrent_version_retention_days
      newer_noncurrent_versions = var.noncurrent_versions_to_retain
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  depends_on = [aws_s3_bucket_versioning.state]
}

# Reject any plaintext request. Terraform always uses TLS, so this costs
# nothing and closes an audit finding.
data "aws_iam_policy_document" "state" {
  statement {
    sid    = "DenyInsecureTransport"
    effect = "Deny"

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    actions = ["s3:*"]

    resources = [
      aws_s3_bucket.state.arn,
      "${aws_s3_bucket.state.arn}/*",
    ]

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "state" {
  bucket = aws_s3_bucket.state.id
  policy = data.aws_iam_policy_document.state.json

  depends_on = [aws_s3_bucket_public_access_block.state]
}

# -----------------------------------------------------------------------------
# Lock table
# -----------------------------------------------------------------------------

resource "aws_dynamodb_table" "lock" {
  count = var.create_lock_table ? 1 : 0

  name = var.lock_table_name

  # On-demand: lock traffic is a handful of requests per apply, so provisioned
  # capacity would be pure waste.
  billing_mode = "PAY_PER_REQUEST"

  # The attribute name is fixed by Terraform's S3 backend contract.
  hash_key = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  point_in_time_recovery {
    enabled = var.lock_table_point_in_time_recovery
  }

  server_side_encryption {
    enabled     = var.kms_key_arn != null
    kms_key_arn = var.kms_key_arn
  }

  tags = merge(local.common_tags, {
    Name = var.lock_table_name
  })
}
