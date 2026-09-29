terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.40.0, < 7.0.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

# No-code modules run as the root module of their workspace, so the provider
# is configured here. Credentials come from the workspace (dynamic provider
# credentials or a variable set), never from module variables.
provider "aws" {
  region = var.region

  default_tags {
    tags = local.common_tags
  }
}


