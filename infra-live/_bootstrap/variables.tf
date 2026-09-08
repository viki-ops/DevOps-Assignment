variable "region" {
  description = "Region for the state and kOps buckets. Must match the region the platform runs in so node boots read state locally."
  type        = string
  default     = "eu-north-1"
}

variable "project" {
  description = "Project name used in tags and resource naming."
  type        = string
  default     = "platform"
}

variable "owner" {
  description = "Owner tag value."
  type        = string
  default     = "viki-ops"
}

variable "state_bucket_name" {
  description = "Terraform remote state bucket."
  type        = string
  default     = "platform-tfstate-eun1-125788629837"
}

variable "lock_table_name" {
  description = "DynamoDB table for Terraform state locking."
  type        = string
  default     = "platform-tflocks"
}

variable "kops_state_bucket_name" {
  description = "kOps cluster state store (KOPS_STATE_STORE)."
  type        = string
  default     = "platform-kops-state-eun1-125788629837"
}
