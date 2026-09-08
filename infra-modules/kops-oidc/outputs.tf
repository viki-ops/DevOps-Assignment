output "issuer_url" {
  description = "OIDC issuer URL, including the https:// scheme. The kOps cluster spec must pin kubeAPIServer.serviceAccountIssuer to exactly this value."
  value       = local.issuer_url
}

output "issuer_hostname" {
  description = "OIDC issuer without the scheme. This is the form that appears in the `sub`/`aud` conditions of IRSA trust policies."
  value       = local.issuer_hostname
}

output "discovery_store" {
  description = "Value for the kOps cluster spec field serviceAccountIssuerDiscovery.discoveryStore."
  value       = "s3://${aws_s3_bucket.oidc.id}"
}

output "jwks_uri" {
  description = "Value for the kOps cluster spec field kubeAPIServer.serviceAccountJWKSURI."
  value       = "${local.issuer_url}/openid/v1/jwks"
}

output "oidc_provider_arn" {
  description = "ARN of the IAM OIDC provider. Every IRSA role trusts this principal."
  value       = aws_iam_openid_connect_provider.this.arn
}

output "bucket_name" {
  description = "Name of the discovery bucket."
  value       = aws_s3_bucket.oidc.id
}

output "bucket_arn" {
  description = "ARN of the discovery bucket."
  value       = aws_s3_bucket.oidc.arn
}
