variable "cluster_name" {
  description = "kOps cluster name."
  type        = string
}

variable "kms_key_arn" {
  description = "Platform CMK ARN used for etcd and root volume encryption."
  type        = string
}

variable "oidc_bucket_arn" {
  description = "ARN of the OIDC discovery bucket the control plane publishes to and nodes read from."
  type        = string
}

variable "tags" {
  description = "Tags. Accepted for interface consistency; this module emits policy documents rather than creating taggable resources."
  type        = map(string)
  default     = {}
}
