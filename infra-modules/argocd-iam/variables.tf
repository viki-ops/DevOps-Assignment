variable "name_prefix" {
  description = "Prefix for IAM role and policy names, e.g. \"platform-dev\"."
  type        = string
}

variable "region" {
  description = "AWS region, used to build ECR and Secrets Manager ARNs."
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

variable "argocd_namespace" {
  description = "Namespace ArgoCD runs in. Part of the trust policy's sub claim, so it must match the actual install."
  type        = string
  default     = "argocd"
}

variable "kms_key_arn" {
  description = "Platform CMK ARN that ArgoCD may decrypt with."
  type        = string
}

variable "secret_name_prefix" {
  description = "Secrets Manager path prefix; ArgoCD may read <prefix>/argocd/*."
  type        = string
  default     = "platform"
}

variable "tags" {
  description = "Tags applied to the role and policy."
  type        = map(string)
  default     = {}
}
