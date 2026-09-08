terraform {
  required_version = ">= 1.9.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0, < 7.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = ">= 4.0"
    }
    local = {
      source  = "hashicorp/local"
      version = ">= 2.4"
    }
  }
}

provider "aws" {
  region = var.region

  # Applied to every taggable resource in the stack. Cost allocation and the
  # teardown leak-check both rely on these being consistent - `make destroy`
  # verifies nothing tagged Environment=dev survives.
  default_tags {
    tags = {
      Project     = var.project
      Environment = var.environment
      ManagedBy   = "terraform"
      Stack       = "infra-live/dev"
      Owner       = var.owner
      Cluster     = var.cluster_name
    }
  }
}
