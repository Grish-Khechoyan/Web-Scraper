terraform {
  backend "s3" {
    bucket       = "project-genesis-tf-state-vboxuser-98765"
    key          = "project-genesis/terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true
  }
}

provider "aws" {
  region = var.aws_region
}
