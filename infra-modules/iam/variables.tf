variable "name_prefix" {
  description = "Prefix for all IAM role and policy names, e.g. \"platform-dev\"."
  type        = string
}

variable "cluster_name" {
  description = "kOps cluster name. Used in the cluster-autoscaler tag condition so it may only scale this cluster's ASGs."
  type        = string
}

variable "region" {
  description = "AWS region, used to build Secrets Manager and SSM resource ARNs."
  type        = string
}

variable "oidc_provider_arn" {
  description = "ARN of the IAM OIDC provider (kops-oidc module output)."
  type        = string
}

variable "oidc_issuer_hostname" {
  description = "OIDC issuer hostname without scheme (kops-oidc module output)."
  type        = string
}

variable "route53_zone_arn" {
  description = "ARN of the hosted zone external-dns and cert-manager may write to. Scoping to a single zone is what keeps these roles least-privilege."
  type        = string
}

variable "route53_zone_name" {
  description = "Hosted zone name, used only in role descriptions."
  type        = string
}

variable "kms_key_arn" {
  description = "Platform CMK ARN, granted to External Secrets (decrypt) and the EBS CSI driver (volume encryption)."
  type        = string
}

variable "secret_name_prefix" {
  description = "Secrets Manager and SSM path prefix that External Secrets may read, e.g. \"platform/dev\"."
  type        = string
  default     = "platform"
}

variable "tags" {
  description = "Tags applied to every role and policy."
  type        = map(string)
  default     = {}
}
