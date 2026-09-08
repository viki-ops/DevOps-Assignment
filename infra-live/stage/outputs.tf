# =============================================================================
# Outputs.
#
# These are the contract between Terraform and everything downstream. In
# particular `kops_cluster_inputs` is read verbatim by
# cluster-ops/playbooks/cluster-create.yml via `terraform output -json`, so the
# kOps manifest is generated from real infrastructure IDs rather than
# hand-copied values.
# =============================================================================

# --- Networking ---------------------------------------------------------------

output "vpc_id" {
  description = "VPC ID."
  value       = module.vpc.vpc_id
}

output "vpc_cidr_block" {
  description = "VPC CIDR."
  value       = module.vpc.vpc_cidr_block
}

output "private_subnet_ids" {
  description = "Private subnet IDs (nodes)."
  value       = module.vpc.private_subnet_ids
}

output "public_subnet_ids" {
  description = "Public/utility subnet IDs (NAT, bastion, internet-facing LBs)."
  value       = module.vpc.public_subnet_ids
}

output "private_subnets_by_az" {
  description = "AZ to private subnet ID."
  value       = module.vpc.private_subnets_by_az
}

output "public_subnets_by_az" {
  description = "AZ to public subnet ID."
  value       = module.vpc.public_subnets_by_az
}

output "nat_public_ips" {
  description = "Stable egress IPs of the cluster."
  value       = module.vpc.nat_public_ips
}

output "nat_gateway_by_az" {
  description = "AZ to NAT gateway ID; rendered into the kOps subnet egress field."
  value       = module.vpc.nat_gateway_by_az
}

# --- DNS ----------------------------------------------------------------------

output "hosted_zone_id" {
  description = "Route53 private hosted zone ID."
  value       = module.dns.zone_id
}

output "hosted_zone_name" {
  description = "Route53 private hosted zone name."
  value       = module.dns.zone_name
}

# --- Encryption ---------------------------------------------------------------

output "kms_key_arn" {
  description = "Platform CMK ARN. Referenced by the kOps spec for etcd volume encryption."
  value       = module.kms.key_arn
}

output "kms_key_alias" {
  description = "Platform CMK alias."
  value       = module.kms.alias_name
}

# --- IRSA ---------------------------------------------------------------------

output "oidc_issuer_url" {
  description = "OIDC issuer URL. Pinned verbatim into kubeAPIServer.serviceAccountIssuer."
  value       = module.kops_oidc.issuer_url
}

output "oidc_issuer_hostname" {
  description = "OIDC issuer without scheme."
  value       = module.kops_oidc.issuer_hostname
}

output "oidc_provider_arn" {
  description = "IAM OIDC provider ARN that every IRSA role trusts."
  value       = module.kops_oidc.oidc_provider_arn
}

output "oidc_discovery_store" {
  description = "Value for spec.serviceAccountIssuerDiscovery.discoveryStore."
  value       = module.kops_oidc.discovery_store
}

output "oidc_jwks_uri" {
  description = "Value for spec.kubeAPIServer.serviceAccountJWKSURI."
  value       = module.kops_oidc.jwks_uri
}

output "irsa_role_arns" {
  description = "Add-on IRSA role ARNs keyed by component. Consumed by the Helm platform chart values."
  value       = module.iam.role_arns
}

output "argocd_role_arn" {
  description = "IRSA role ARN for the ArgoCD repo-server and application-controller."
  value       = module.argocd_iam.repo_server_role_arn
}

# --- SSH ----------------------------------------------------------------------

output "bastion_public_key" {
  description = "Public key kOps installs on the bastion and nodes."
  value       = tls_private_key.bastion.public_key_openssh
}

output "bastion_private_key_path" {
  description = "Local path to the bastion private key (gitignored, mode 0600)."
  value       = local_sensitive_file.bastion_private_key.filename
}

# --- Aggregate contract for kOps ----------------------------------------------

output "kops_cluster_inputs" {
  description = <<-EOT
    Everything cluster-ops needs to render the kOps cluster manifest, in one
    object. Deliberately a single output so the Ansible side has one contract to
    depend on rather than a dozen individually-named outputs that drift.
  EOT
  value = {
    cluster_name = var.cluster_name
    region       = var.region
    azs          = var.azs

    vpc_id          = module.vpc.vpc_id
    vpc_cidr        = module.vpc.vpc_cidr_block
    private_subnets = module.vpc.private_subnets_by_az
    public_subnets  = module.vpc.public_subnets_by_az
    nat_by_az       = module.vpc.nat_gateway_by_az

    kms_key_arn = module.kms.key_arn

    oidc_issuer_url      = module.kops_oidc.issuer_url
    oidc_discovery_store = module.kops_oidc.discovery_store
    oidc_jwks_uri        = module.kops_oidc.jwks_uri

    additional_policies = module.cluster_iam.additional_policies

    hosted_zone_id   = module.dns.zone_id
    hosted_zone_name = module.dns.zone_name

    ssh_public_key = tls_private_key.bastion.public_key_openssh

    irsa_role_arns  = module.iam.role_arns
    argocd_role_arn = module.argocd_iam.repo_server_role_arn
  }
}
