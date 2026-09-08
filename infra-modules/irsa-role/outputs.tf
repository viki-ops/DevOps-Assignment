output "role_arn" {
  description = "ARN of the IRSA role. This is the value for the eks.amazonaws.com/role-arn annotation on the ServiceAccount."
  value       = aws_iam_role.this.arn
}

output "role_name" {
  description = "Name of the IRSA role."
  value       = aws_iam_role.this.name
}

output "policy_arn" {
  description = "ARN of the customer-managed policy, or null when create_managed_policy is false."
  value       = var.create_managed_policy ? aws_iam_policy.managed[0].arn : null
}

output "service_account_annotation" {
  description = "Ready-to-use ServiceAccount annotation map for Helm values."
  value = {
    "eks.amazonaws.com/role-arn" = aws_iam_role.this.arn
  }
}

output "trusted_subjects" {
  description = "The exact sub claims permitted by the trust policy. Useful for debugging \"AccessDenied: Not authorized to perform sts:AssumeRoleWithWebIdentity\"."
  value       = local.subjects
}
