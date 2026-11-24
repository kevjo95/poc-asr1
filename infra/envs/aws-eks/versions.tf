terraform {
  required_version = ">= 1.5"
  required_providers {
    aws     = { source = "hashicorp/aws", version = "~> 5.95" } # el módulo EKS 20.x exige >= 5.95 y < 6
    archive = { source = "hashicorp/archive", version = "~> 2.4" }
  }
}

provider "aws" {
  region  = var.region
  profile = var.aws_profile
  default_tags {
    tags = { project = "poc-asr1", managed_by = "terraform", purpose = "universidad-poc" }
  }
}
