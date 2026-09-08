output "bucket_name" {
  description = "Name of the state bucket."
  value       = aws_s3_bucket.state.id
}

output "bucket_arn" {
  description = "ARN of the state bucket."
  value       = aws_s3_bucket.state.arn
}

output "bucket_region" {
  description = "Region the state bucket lives in. Must match the `region` set in every consuming backend block."
  value       = aws_s3_bucket.state.region
}

output "lock_table_name" {
  description = "Name of the DynamoDB lock table, or null when create_lock_table is false."
  value       = var.create_lock_table ? aws_dynamodb_table.lock[0].name : null
}

output "lock_table_arn" {
  description = "ARN of the DynamoDB lock table, or null when create_lock_table is false."
  value       = var.create_lock_table ? aws_dynamodb_table.lock[0].arn : null
}

output "backend_config" {
  description = "Ready-to-paste backend block contents for consuming stacks."
  value = {
    bucket         = aws_s3_bucket.state.id
    region         = aws_s3_bucket.state.region
    dynamodb_table = var.create_lock_table ? aws_dynamodb_table.lock[0].name : null
    encrypt        = true
  }
}
