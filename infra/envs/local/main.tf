terraform {
  required_version = ">= 1.5"
  required_providers {
    aws     = { source = "hashicorp/aws", version = "~> 5.0" }
    archive = { source = "hashicorp/archive", version = "~> 2.4" }
  }
}

variable "localstack_endpoint" {
  type    = string
  default = "http://localhost:4566"
}
variable "simulated_failure_rate" {
  type    = number
  default = 0
}

provider "aws" {
  region                      = "us-east-1"
  access_key                  = "test"
  secret_key                  = "test"
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true

  endpoints {
    sqs      = var.localstack_endpoint
    dynamodb = var.localstack_endpoint
    lambda   = var.localstack_endpoint
    iam      = var.localstack_endpoint
    sts      = var.localstack_endpoint
    logs     = var.localstack_endpoint
  }
}

module "stack" {
  source                 = "../../modules/stack"
  reconciler_source_dir  = "${path.module}/../../../services/reconciler-lambda"
  simulated_failure_rate = var.simulated_failure_rate
}

output "queue_url" { value = module.stack.queue_url }
output "queue_name" { value = module.stack.queue_name }
output "dlq_url" { value = module.stack.dlq_url }
output "table_name" { value = module.stack.table_name }
output "function_name" { value = module.stack.function_name }
