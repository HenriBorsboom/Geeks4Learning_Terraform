# Creates the S3 bucket and DynamoDB table used as the remote backend for all
# three environments. Run once with `terraform apply` before initialising any
# environment. This config stores its own state locally (never commit it).

resource "aws_s3_bucket" "terraform_state" {
  bucket = "borsboomh-tfstate"

  tags = {
    Name    = "borsboomh-tfstate"
    Purpose = "Terraform remote state storage"
  }
}

# Versioning allows recovery of a previous state file if one is accidentally
# overwritten or corrupted.
resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.terraform_state.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Encrypt state at rest — state files can contain sensitive resource attributes.
resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.terraform_state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# State must never be publicly readable.
resource "aws_s3_bucket_public_access_block" "state" {
  bucket                  = aws_s3_bucket.terraform_state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

output "state_bucket_name" {
  value       = aws_s3_bucket.terraform_state.id
  description = "S3 bucket name to use in each environment backend.tf"
}
