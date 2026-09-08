output "state_bucket_name" {
  description = "Terraform state bucket. Referenced by every other stack's backend block."
  value       = module.state_backend.bucket_name
}

output "lock_table_name" {
  description = "DynamoDB lock table name."
  value       = module.state_backend.lock_table_name
}

output "region" {
  description = "Region holding the state and kOps buckets."
  value       = var.region
}

output "kops_state_bucket" {
  description = "kOps state store bucket name."
  value       = aws_s3_bucket.kops_state.id
}

output "kops_state_store" {
  description = "Value for KOPS_STATE_STORE / the Ansible kops_state_store variable."
  value       = "s3://${aws_s3_bucket.kops_state.id}"
}
