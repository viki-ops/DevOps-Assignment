terraform {
  backend "s3" {
    bucket = "platform-tfstate-eun1-125788629837"

    # Per-environment state separation. prod, stage and prod each own a distinct
    # key in the same bucket, so a mistake in one environment cannot corrupt
    # another's state, and each can be locked independently.
    key    = "prod/terraform.tfstate"
    region = "eu-north-1"

    # The brief asks for DynamoDB locking, so the table is used.
    #
    # Terraform 1.10+ deprecated this in favour of `use_lockfile`, which locks
    # with a conditional-write S3 object and removes the DynamoDB dependency
    # entirely. Both are enabled here: that is the documented migration path and
    # means the state is protected even if one mechanism is later removed.
    dynamodb_table = "platform-tflocks"
    use_lockfile   = true

    encrypt = true
  }
}
