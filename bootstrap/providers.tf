# Bootstrap uses local state — no backend block here.
# The S3 bucket and DynamoDB table that all other configs depend on do not exist yet,
# so there is nowhere to store remote state at this point.
terraform {
  required_version = ">= 1.3"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = "af-south-1"
}
