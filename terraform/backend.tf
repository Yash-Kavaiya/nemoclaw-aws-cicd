terraform {
  backend "s3" {
    # Update these values before running terraform init
    bucket         = "your-nemoclaw-tfstate"      # Replace with your S3 bucket name
    key            = "nemoclaw/terraform.tfstate"
    region         = "us-east-1"                  # Replace with your region
    encrypt        = true
    dynamodb_table = "nemoclaw-tfstate-lock"       # DynamoDB table for state locking
  }
}
