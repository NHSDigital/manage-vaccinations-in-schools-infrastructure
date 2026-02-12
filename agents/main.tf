terraform {
  required_version = "~> 1.13.3"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.2"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.7"
    }
  }

  backend "s3" {
    bucket       = "nhse-mavis-terraform-state"
    key          = "terraform-agents-development.tfstate"
    region       = "eu-west-2"
    use_lockfile = true
    encrypt      = true
  }
}

provider "aws" {
  region = "eu-west-2"

  default_tags {
    tags = {
      Environment = "development"
    }
  }
}

data "aws_caller_identity" "current" {}

check "account_id" {
  assert {
    condition     = data.aws_caller_identity.current.account_id == "393416225559"
    error_message = "This configuration must only be applied to the development account (393416225559)."
  }
}

locals {
  account_id = data.aws_caller_identity.current.account_id
}
