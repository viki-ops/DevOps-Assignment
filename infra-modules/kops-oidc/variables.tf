variable "bucket_name" {
  description = <<-EOT
    Name of the public OIDC discovery bucket. This name determines the OIDC
    issuer URL (https://<bucket_name>.s3.<region>.amazonaws.com), so changing it
    invalidates every IRSA trust policy and requires a cluster rebuild.

    Must be a separate bucket from the Terraform state store and from the kOps
    state store, both of which are private.
  EOT
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.bucket_name))
    error_message = "bucket_name must be a valid, DNS-compliant S3 bucket name (lowercase, 3-63 chars)."
  }

  validation {
    condition     = !can(regex("\\.", var.bucket_name))
    error_message = "bucket_name must not contain dots: virtual-hosted-style HTTPS requires a wildcard-cert-compatible hostname, and a dotted bucket name breaks TLS validation for the OIDC issuer."
  }
}

variable "tags" {
  description = "Tags applied to the bucket and OIDC provider."
  type        = map(string)
  default     = {}
}

variable "token_audiences" {
  description = <<-EOT
    Audiences ("aud" claim values) the IAM OIDC provider will accept.

    Defaults to both the kOps audience and the EKS one. kOps is the
    load-bearing entry: its pod-identity-webhook and every kOps-managed addon
    project tokens with audience "amazonaws.com".
  EOT
  type        = list(string)
  default     = ["amazonaws.com", "sts.amazonaws.com"]

  validation {
    condition     = contains(var.token_audiences, "amazonaws.com")
    error_message = "amazonaws.com must be included: kOps addons and the pod-identity-webhook project tokens with that audience, and omitting it prevents the cloud controller manager from authenticating at all."
  }
}
