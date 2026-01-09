terraform {
  backend "s3" {
    bucket         = "ml-pipeline-terraform-state-255638996405"
    key            = "ml-pipeline/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "ml-pipeline-terraform-locks"
    encrypt        = true
  }
}
