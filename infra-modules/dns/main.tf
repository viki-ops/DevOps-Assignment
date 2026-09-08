# =============================================================================
# Route53 hosted zone for the platform.
#
# Defaults to a PRIVATE zone, which is not a cost compromise but a
# correctness requirement: the brief's example domain is
# `corp.example.internal`, and ICANN board resolution 2024.07.29.06
# permanently reserved `.internal` from delegation in the DNS root zone. A
# public zone for that name could never resolve for anybody.
#
# The module still supports public zones (set `private = false`) so that
# registering a real domain later is a one-variable change. See
# docs/adr/0002-dns-topology.md.
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
    Module    = "infra-modules/dns"
  })
}

resource "aws_route53_zone" "this" {
  name    = var.zone_name
  comment = var.comment

  # A private zone is defined by having at least one VPC association.
  dynamic "vpc" {
    for_each = var.private ? var.vpc_associations : []

    content {
      vpc_id     = vpc.value.vpc_id
      vpc_region = vpc.value.vpc_region
    }
  }

  # force_destroy lets `terraform destroy` remove the zone even though
  # external-dns will have created records inside it that Terraform does not
  # track. Without this, teardown fails with HostedZoneNotEmpty.
  force_destroy = var.force_destroy

  tags = merge(local.common_tags, {
    Name = var.zone_name
  })

  lifecycle {
    precondition {
      condition     = !var.private || length(var.vpc_associations) > 0
      error_message = "A private hosted zone requires at least one VPC association."
    }
  }
}
