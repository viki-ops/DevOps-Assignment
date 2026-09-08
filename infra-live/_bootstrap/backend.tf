# Added AFTER the first local-state apply, then activated with:
#
#   terraform init -migrate-state
#
# This is what closes the bootstrap loop: the stack that created the state
# bucket ends up storing its own state in that bucket, so no stack anywhere in
# this repo keeps state on a laptop.

terraform {
  backend "s3" {
    bucket         = "platform-tfstate-eun1-125788629837"
    key            = "bootstrap/terraform.tfstate"
    region         = "eu-north-1"
    dynamodb_table = "platform-tflocks"
    encrypt        = true
  }
}
