output "key_id" {
  description = "KMS key ID."
  value       = aws_kms_key.this.key_id
}

output "key_arn" {
  description = "KMS key ARN. This is what the kOps cluster manifest references for etcd volume encryption."
  value       = aws_kms_key.this.arn
}

output "alias_name" {
  description = "Full alias, including the \"alias/\" prefix."
  value       = aws_kms_alias.this.name
}

output "alias_arn" {
  description = "Alias ARN."
  value       = aws_kms_alias.this.arn
}
