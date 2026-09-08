terraform {
  required_version = ">= 1.9.0"

  required_providers {
    aws = {
      source = "hashicorp/aws"
      # Pinned to the v6 major line: this module uses
      # data.aws_region.current.region, which replaced the deprecated .name
      # attribute in provider v6.
      version = ">= 6.0, < 7.0"
    }
  }
}
