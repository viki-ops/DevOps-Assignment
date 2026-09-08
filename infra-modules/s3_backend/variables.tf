variable "bucket_name" {
  description = "Globally unique name for the Terraform state bucket. Convention: <project>-tfstate-<account_id>."
  type        = string
}

variable "create_lock_table" {
  description = "Create the DynamoDB state lock table. Terraform 1.10+ can lock natively in S3 via use_lockfile, but the brief asks for DynamoDB."
  type        = bool
  default     = true
}

variable "lock_table_name" {
  description = "Name of the DynamoDB lock table."
  type        = string
  default     = "terraform-locks"
}

variable "lock_table_point_in_time_recovery" {
  description = "Enable PITR on the lock table. Off by default: the table holds only ephemeral lock records, so there is nothing worth restoring."
  type        = bool
  default     = false
}

variable "kms_key_arn" {
  description = "CMK for bucket and lock table encryption. Null uses SSE-S3 (AES256), which avoids a hard dependency from the bootstrap stack onto the KMS stack."
  type        = string
  default     = null
}

variable "noncurrent_version_retention_days" {
  description = "Days to retain non-current state object versions."
  type        = number
  default     = 90
}

variable "noncurrent_versions_to_retain" {
  description = "Number of recent non-current versions always retained, regardless of age."
  type        = number
  default     = 10
}

variable "tags" {
  description = "Tags applied to the bucket and lock table."
  type        = map(string)
  default     = {}
}
