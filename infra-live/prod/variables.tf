variable "region" {
  description = "AWS region for this environment."
  type        = string
  default     = "eu-north-1"
}

variable "project" {
  description = "Project name, used as a prefix for resource names and tags."
  type        = string
  default     = "platform"
}

variable "environment" {
  description = "Environment name."
  type        = string
  default     = "prod"
}

variable "owner" {
  description = "Owner tag value."
  type        = string
  default     = "viki-ops"
}

variable "cluster_name" {
  description = <<-EOT
    kOps cluster name.

    The ".k8s.local" suffix selects None-DNS topology, which is what lets this
    cluster exist without a registered public domain: kOps publishes no DNS
    records and writes the API load balancer's AWS hostname into kubeconfig
    instead. See docs/adr/0002-dns-topology.md.

    Immutable after cluster creation.
  EOT
  type        = string
  default     = "prod.k8s.local"
}

variable "vpc_cidr" {
  description = "CIDR for this environment's VPC. Environments use distinct ranges so they could be peered later without collision."
  type        = string
  default     = "10.20.0.0/16"
}

variable "azs" {
  description = "Availability zones. Three are required for an odd etcd quorum."
  type        = list(string)
  default     = ["eu-north-1a", "eu-north-1b", "eu-north-1c"]
}

variable "private_subnet_cidrs" {
  description = "Private subnet CIDRs (nodes). /19 each: 8,190 usable addresses, ample headroom for autoscaling."
  type        = list(string)
  default     = ["10.20.0.0/19", "10.20.32.0/19", "10.20.64.0/19"]
}

variable "public_subnet_cidrs" {
  description = "Public/utility subnet CIDRs (NAT, bastion, internet-facing load balancers). /22 is plenty - only infrastructure lives here."
  type        = list(string)
  default     = ["10.20.96.0/22", "10.20.100.0/22", "10.20.104.0/22"]
}

variable "nat_gateway_count" {
  description = "NAT gateways. Two satisfies the brief's minimum and costs roughly half of full per-AZ isolation."
  type        = number
  default     = 2
}

variable "dns_zone_name" {
  description = "Route53 zone name. Private by necessity: ICANN permanently reserved .internal from root-zone delegation, so this name can never resolve publicly."
  type        = string
  default     = "corp.example.internal"
}

variable "oidc_bucket_name" {
  description = "Public OIDC discovery bucket. Determines the IRSA issuer URL, so changing it invalidates every IRSA trust policy."
  type        = string
  default     = "platform-prod-oidc-eun1-125788629837"
}

variable "argocd_namespace" {
  description = "Namespace ArgoCD is installed into; forms part of its IRSA trust policy."
  type        = string
  default     = "argocd"
}

variable "enable_flow_logs" {
  description = "Enable VPC flow logs. Off in prod to avoid CloudWatch ingestion charges on a short-lived environment."
  type        = bool
  default     = false
}
