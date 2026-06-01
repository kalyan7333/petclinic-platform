# Run scripts/bootstrap-state.sh first to create the S3 bucket and DynamoDB table.
# Replace ACCOUNT_ID with your AWS account ID, or run:
#   ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

terraform {
  backend "s3" {
    bucket       = "pet-terraform-state-325779841182"
    key          = "petclinic/prod/terraform.tfstate"
    region       = "eu-central-1"
    encrypt      = true
    use_lockfile = true
  }
}
