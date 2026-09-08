# =============================================================================
# IRSA foundation: the OIDC discovery bucket and the IAM OIDC provider.
#
# WHO OWNS THE OIDC PROVIDER
# --------------------------
# kOps can create the IAM OIDC provider itself via
# `serviceAccountIssuerDiscovery.enableAWSOIDCProvider: true`. We deliberately
# do NOT use that, because the brief requires Terraform to provision IRSA and
# to export the OIDC issuer as a stack output.
#
# That normally creates a chicken-and-egg problem - Terraform needs the issuer
# URL, which kOps only decides at cluster-creation time. We break the cycle by
# making the issuer URL deterministic and then pinning it from both sides:
#
#   1. Terraform creates bucket `<name>` and therefore knows the issuer will be
#      https://<name>.s3.<region>.amazonaws.com
#   2. Terraform creates the IAM OIDC provider for exactly that URL.
#   3. The kOps cluster template sets `discoveryStore: s3://<name>` AND pins
#      `kubeAPIServer.serviceAccountIssuer` / `serviceAccountJWKSURI` to the
#      same URL explicitly, rather than relying on kOps to derive it.
#   4. kOps runs with `enableAWSOIDCProvider: false`, so it publishes the
#      discovery documents but never touches IAM.
#
# Pinning in step 3 is what makes this safe: if kOps ever changed how it
# derives the URL, the cluster spec would still agree with the IAM provider.
#
# WHY THE BUCKET IS PUBLIC
# ------------------------
# This is intentional and is not a misconfiguration. AWS STS fetches
# /.well-known/openid-configuration and /openid/v1/jwks anonymously when
# validating a web identity token, so the discovery documents must be
# world-readable. They contain only public JWKS signing keys - no secrets. The
# bucket holds nothing else, and a policy restricts anonymous access to
# GetObject on exactly those paths.
# =============================================================================

terraform {
  required_version = ">= 1.9.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0, < 7.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = ">= 4.0"
    }
  }
}

data "aws_region" "current" {}

locals {
  region = data.aws_region.current.region

  # The canonical, virtual-hosted-style regional endpoint. This exact string
  # becomes the OIDC issuer and must match the kOps cluster spec byte for byte.
  issuer_url      = "https://${var.bucket_name}.s3.${local.region}.amazonaws.com"
  issuer_hostname = "${var.bucket_name}.s3.${local.region}.amazonaws.com"

  common_tags = merge(var.tags, {
    ManagedBy = "terraform"
    Module    = "infra-modules/kops-oidc"
    Purpose   = "irsa-oidc-discovery"
  })
}

# -----------------------------------------------------------------------------
# Discovery bucket
# -----------------------------------------------------------------------------

resource "aws_s3_bucket" "oidc" {
  bucket = var.bucket_name

  # Safe to empty on destroy: it holds only regenerable public discovery
  # documents, and leaving it behind would block a clean teardown.
  force_destroy = true

  tags = merge(local.common_tags, {
    Name = var.bucket_name
  })
}

# kOps writes the discovery objects with a public-read ACL, so object ACLs must
# remain enabled. BucketOwnerEnforced (the modern default) would make kOps'
# write fail with AccessControlListNotSupported.
resource "aws_s3_bucket_ownership_controls" "oidc" {
  bucket = aws_s3_bucket.oidc.id

  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

# Every one of these must be false, otherwise the public-read ACL and the
# anonymous GetObject policy below are silently overridden and STS receives a
# 403 when it tries to fetch the JWKS.
resource "aws_s3_bucket_public_access_block" "oidc" {
  bucket = aws_s3_bucket.oidc.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_acl" "oidc" {
  bucket = aws_s3_bucket.oidc.id
  acl    = "public-read"

  depends_on = [
    aws_s3_bucket_ownership_controls.oidc,
    aws_s3_bucket_public_access_block.oidc,
  ]
}

resource "aws_s3_bucket_server_side_encryption_configuration" "oidc" {
  bucket = aws_s3_bucket.oidc.id

  rule {
    apply_server_side_encryption_by_default {
      # Must stay SSE-S3. A CMK would require anonymous readers to hold
      # kms:Decrypt, which is impossible, and STS would fail to fetch the JWKS.
      sse_algorithm = "AES256"
    }
  }
}

# Anonymous read is scoped to GetObject on the two discovery paths only - not
# to the bucket, not to ListBucket, not to anything else.
data "aws_iam_policy_document" "oidc" {
  statement {
    sid    = "AllowAnonymousDiscoveryReads"
    effect = "Allow"

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    actions = ["s3:GetObject"]

    resources = [
      "${aws_s3_bucket.oidc.arn}/.well-known/*",
      "${aws_s3_bucket.oidc.arn}/openid/*",
    ]
  }

  statement {
    sid    = "DenyInsecureTransport"
    effect = "Deny"

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    actions = ["s3:*"]

    resources = [
      aws_s3_bucket.oidc.arn,
      "${aws_s3_bucket.oidc.arn}/*",
    ]

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "oidc" {
  bucket = aws_s3_bucket.oidc.id
  policy = data.aws_iam_policy_document.oidc.json

  depends_on = [aws_s3_bucket_public_access_block.oidc]
}

# -----------------------------------------------------------------------------
# IAM OIDC provider
# -----------------------------------------------------------------------------

# Read the TLS chain presented by the S3 endpoint so the thumbprint is derived
# rather than hard-coded. Hard-coding Amazon's root CA fingerprint works until
# the day AWS rotates it, at which point every IRSA role breaks at once.
data "tls_certificate" "s3" {
  url = local.issuer_url
}

locals {
  # STS wants the SHA-1 fingerprint of the CA at the top of the issuer's chain,
  # not the leaf serving certificate.
  #
  # hashicorp/tls returns the chain ordered root-first, so index 0 is the CA
  # and the last element is the leaf (CN=*.s3.<region>.amazonaws.com). Taking
  # the last element instead is wrong twice over: it is not the CA, and AWS
  # rotates that certificate every few months. The mistake is invisible at
  # apply time and only surfaces when a workload first authenticates:
  #
  #   InvalidIdentityToken: The web identity token provided could not be
  #   validated.
  #
  # Selecting "the self-signed cert" does not work here either: Amazon Root
  # CA 1 is cross-signed by Starfield, so its issuer differs from its subject.
  oidc_chain      = data.tls_certificate.s3.certificates
  oidc_thumbprint = local.oidc_chain[0].sha1_fingerprint
}

resource "aws_iam_openid_connect_provider" "this" {
  url = local.issuer_url

  # STS refuses any token whose "aud" claim is absent from this list, with the
  # generic "InvalidIdentityToken" error.
  #
  # "amazonaws.com" must be present and is the one that actually matters here:
  # kOps projects every addon token with that audience and runs its
  # pod-identity-webhook with --token-audience=amazonaws.com. Listing only the
  # EKS-conventional "sts.amazonaws.com" leaves the cluster in a state where
  # nodes never leave the uninitialized taint, because the AWS cloud
  # controller manager itself cannot authenticate.
  #
  # "sts.amazonaws.com" is kept for SDKs and tooling that request the EKS
  # audience explicitly.
  client_id_list = var.token_audiences

  thumbprint_list = [local.oidc_thumbprint]

  tags = merge(local.common_tags, {
    Name = "${var.bucket_name}-oidc"
  })

  lifecycle {
    # Assert the chain really is ordered root-first before trusting index 0.
    # The CA must be the issuer of the certificate below it; if hashicorp/tls
    # ever reverses the ordering, this fails the apply instead of quietly
    # registering the leaf fingerprint and breaking every IRSA role.
    precondition {
      condition = (
        length(local.oidc_chain) >= 2 &&
        local.oidc_chain[0].subject == local.oidc_chain[1].issuer
      )
      error_message = <<-EOT
        The TLS chain served by ${local.issuer_url} is not ordered root-first:
        certificate[0] (${try(local.oidc_chain[0].subject, "none")}) is not the
        issuer of certificate[1]. Refusing to guess the OIDC thumbprint, since
        the wrong value fails only at runtime with "InvalidIdentityToken".
      EOT
    }
  }
}
