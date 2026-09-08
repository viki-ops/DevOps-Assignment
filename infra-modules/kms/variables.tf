variable "alias_name" {
  description = "Alias for the key, without the \"alias/\" prefix, e.g. \"platform-dev\"."
  type        = string
}

variable "description" {
  description = "Human-readable key description."
  type        = string
  default     = "Platform CMK - etcd, EBS and Kubernetes secret encryption"
}

variable "deletion_window_in_days" {
  description = "Waiting period before a scheduled key deletion completes. 7 is the minimum AWS allows and is appropriate for short-lived environments; use 30 in production."
  type        = number
  default     = 7

  validation {
    condition     = var.deletion_window_in_days >= 7 && var.deletion_window_in_days <= 30
    error_message = "AWS requires the KMS deletion window to be between 7 and 30 days."
  }
}

variable "key_users" {
  description = "IAM principal ARNs granted data-plane use of the key (encrypt/decrypt/grant). Typically the kOps node and control-plane role ARNs."
  type        = list(string)
  default     = []
}

variable "allow_autoscaling_service_linked_role" {
  description = "Grant the AWSServiceRoleForAutoScaling service-linked role use of the key. Required whenever an Auto Scaling group launches instances with encrypted volumes."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags applied to the key."
  type        = map(string)
  default     = {}
}
