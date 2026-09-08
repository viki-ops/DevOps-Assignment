# =============================================================================
# infra-live/dev - AWS foundations for the dev environment.
#
# This stack creates everything the cluster needs to exist but nothing that
# runs inside it. kOps consumes the outputs (see `terraform output -json`,
# which cluster-ops/playbooks/cluster-create.yml reads directly), and the
# add-ons consume the IRSA role ARNs.
#
# Module sources are relative paths during development. `make pin` rewrites
# them to git-pinned refs against this repository before merge, and CI asserts
# that main always carries the pinned form - see scripts/pin-modules.sh.
# =============================================================================

locals {
  name_prefix = "${var.project}-${var.environment}"

  tags = {
    Project     = var.project
    Environment = var.environment
    Cluster     = var.cluster_name
  }
}

data "aws_caller_identity" "current" {}

# -----------------------------------------------------------------------------
# Networking
# -----------------------------------------------------------------------------

module "vpc" {
  source = "../../infra-modules/vpc"

  name       = local.name_prefix
  cidr_block = var.vpc_cidr
  azs        = var.azs

  private_subnet_cidrs = var.private_subnet_cidrs
  public_subnet_cidrs  = var.public_subnet_cidrs
  nat_gateway_count    = var.nat_gateway_count

  cluster_name     = var.cluster_name
  enable_flow_logs = var.enable_flow_logs

  tags = local.tags
}

# -----------------------------------------------------------------------------
# DNS
# -----------------------------------------------------------------------------

module "dns" {
  source = "../../infra-modules/dns"

  zone_name = var.dns_zone_name
  private   = true

  vpc_associations = [{
    vpc_id     = module.vpc.vpc_id
    vpc_region = var.region
  }]

  comment = "Private zone for ${var.cluster_name}; external-dns writes records here via IRSA"

  tags = local.tags
}

# -----------------------------------------------------------------------------
# Encryption
# -----------------------------------------------------------------------------

module "kms" {
  source = "../../infra-modules/kms"

  alias_name  = local.name_prefix
  description = "Platform CMK for ${var.cluster_name}: etcd volumes, node root volumes, application secrets"

  # Deliberately empty. The kOps node and control-plane roles do not exist yet
  # at apply time, so naming them here would fail with MalformedPolicyDocument.
  # Access is instead delegated through IAM: the key policy grants the account
  # root kms:*, which permits IAM policies in this account (the additionalPolicies
  # emitted by the cluster_iam module) to grant use of the key. This is the
  # standard KMS delegation model and avoids an ordering dependency between
  # Terraform and kOps.
  key_users = []

  # Required separately: a service-linked role's access cannot be delegated
  # through an IAM policy we control. Without it, ASG launches of instances with
  # encrypted volumes fail with an opaque Client.InternalError.
  allow_autoscaling_service_linked_role = true

  tags = local.tags
}

# -----------------------------------------------------------------------------
# IRSA foundation
# -----------------------------------------------------------------------------

module "kops_oidc" {
  source = "../../infra-modules/kops-oidc"

  bucket_name = var.oidc_bucket_name
  tags        = local.tags
}

# -----------------------------------------------------------------------------
# IAM: add-on IRSA roles, ArgoCD, and the kOps instance-profile extras
# -----------------------------------------------------------------------------

module "iam" {
  source = "../../infra-modules/iam"

  name_prefix  = local.name_prefix
  cluster_name = var.cluster_name
  region       = var.region

  oidc_provider_arn    = module.kops_oidc.oidc_provider_arn
  oidc_issuer_hostname = module.kops_oidc.issuer_hostname

  route53_zone_arn  = module.dns.zone_arn
  route53_zone_name = module.dns.zone_name

  kms_key_arn        = module.kms.key_arn
  secret_name_prefix = "${var.project}/${var.environment}"

  tags = local.tags
}

module "argocd_iam" {
  source = "../../infra-modules/argocd-iam"

  name_prefix = local.name_prefix
  region      = var.region

  oidc_provider_arn    = module.kops_oidc.oidc_provider_arn
  oidc_issuer_hostname = module.kops_oidc.issuer_hostname

  argocd_namespace   = var.argocd_namespace
  kms_key_arn        = module.kms.key_arn
  secret_name_prefix = "${var.project}/${var.environment}"

  tags = local.tags
}

module "cluster_iam" {
  source = "../../infra-modules/cluster_iam"

  cluster_name    = var.cluster_name
  kms_key_arn     = module.kms.key_arn
  oidc_bucket_arn = module.kops_oidc.bucket_arn

  tags = local.tags
}

# -----------------------------------------------------------------------------
# Bastion SSH key
#
# kOps needs a public key to bake into the bastion and nodes. Generating it here
# keeps `terraform apply` self-sufficient - no manual key creation step, and no
# key pair shared between environments. The private key is written locally with
# 0600 and is gitignored; it is a dev break-glass credential, not a secret worth
# persisting to AWS.
# -----------------------------------------------------------------------------

resource "tls_private_key" "bastion" {
  algorithm = "ED25519"
}

resource "local_sensitive_file" "bastion_private_key" {
  content         = tls_private_key.bastion.private_key_openssh
  filename        = "${path.module}/.ssh/id_ed25519"
  file_permission = "0600"
}

resource "local_file" "bastion_public_key" {
  content         = tls_private_key.bastion.public_key_openssh
  filename        = "${path.module}/.ssh/id_ed25519.pub"
  file_permission = "0644"
}
