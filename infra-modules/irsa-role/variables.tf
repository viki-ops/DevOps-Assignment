variable "role_name" {
  description = "Name of the IAM role."
  type        = string
}

variable "description" {
  description = "Role description."
  type        = string
  default     = "IRSA role managed by Terraform"
}

variable "oidc_provider_arn" {
  description = "ARN of the cluster's IAM OIDC provider (output oidc_provider_arn of the kops-oidc module)."
  type        = string
}

variable "oidc_issuer_hostname" {
  description = "OIDC issuer WITHOUT the https:// scheme, e.g. \"my-bucket.s3.eu-north-1.amazonaws.com\". Used to build the aud/sub condition keys."
  type        = string

  validation {
    condition     = !startswith(var.oidc_issuer_hostname, "https://")
    error_message = "oidc_issuer_hostname must not include the scheme; IAM condition keys are built from the bare hostname."
  }
}

variable "token_audiences" {
  description = <<-EOT
    Accepted values of the <issuer>:aud claim in the trust policy.

    kOps projects service account tokens with audience "amazonaws.com" (its
    pod-identity-webhook runs with --token-audience=amazonaws.com), which is
    NOT the "sts.amazonaws.com" that EKS uses and that most IRSA examples
    show. Both are allowed by default so the roles work whether the token was
    injected by the webhook or requested explicitly by an SDK.
  EOT
  type        = list(string)
  default     = ["amazonaws.com", "sts.amazonaws.com"]

  validation {
    condition     = length(var.token_audiences) > 0
    error_message = "At least one audience is required; an empty list would make the trust policy unsatisfiable."
  }
}

variable "service_accounts" {
  description = "ServiceAccounts permitted to assume this role. Each becomes a system:serviceaccount:<namespace>:<name> entry in the trust policy's sub condition."
  type = list(object({
    namespace = string
    name      = string
  }))

  validation {
    condition     = length(var.service_accounts) > 0
    error_message = "At least one service account must be specified, otherwise the role is unassumable."
  }
}

variable "create_managed_policy" {
  description = "Create a customer-managed policy from policy_json and attach it. Must be a static boolean, not derived from policy_json, because policy documents referencing same-apply resources are unknown at plan time."
  type        = bool
  default     = true
}

variable "policy_json" {
  description = "IAM policy document used when create_managed_policy is true."
  type        = string
  default     = null
}

variable "create_inline_policy" {
  description = "Attach inline_policy_json to the role as an inline policy."
  type        = bool
  default     = false
}

variable "inline_policy_json" {
  description = "IAM policy document used when create_inline_policy is true."
  type        = string
  default     = null
}

variable "additional_policy_arns" {
  description = "Existing policy ARNs to attach (AWS-managed or customer-managed)."
  type        = list(string)
  default     = []
}

variable "max_session_duration" {
  description = "Maximum session duration in seconds. One hour is the default and is ample for controllers that refresh credentials automatically."
  type        = number
  default     = 3600
}

variable "permissions_boundary_arn" {
  description = "Optional permissions boundary ARN capping the role's effective permissions."
  type        = string
  default     = null
}

variable "tags" {
  description = "Tags applied to the role and policy."
  type        = map(string)
  default     = {}
}
