terraform {
  required_version = ">= 1.5"
  required_providers {
    aws     = { source = "hashicorp/aws", version = "~> 5.0" }
    archive = { source = "hashicorp/archive", version = "~> 2.4" }
  }
}

variable "aws_profile" {
  type        = string
  description = "Perfil de AWS de la cuenta personal. Nunca un perfil de trabajo."
}
variable "region" {
  type    = string
  default = "us-east-1"
}
variable "budget_email" {
  type        = string
  description = "Correo para la alarma de presupuesto."
}
variable "budget_usd" {
  type    = number
  default = 10
}

provider "aws" {
  region  = var.region
  profile = var.aws_profile
  default_tags {
    tags = { project = "poc-asr1", managed_by = "terraform" }
  }
}

module "stack" {
  source                = "../../modules/stack"
  reconciler_source_dir = "${path.module}/../../../services/reconciler-lambda"
}

# Guardrail de costo: alarma al 80 % del presupuesto mensual.
resource "aws_budgets_budget" "poc" {
  name         = "poc-asr1-monthly"
  budget_type  = "COST"
  limit_amount = tostring(var.budget_usd)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.budget_email]
  }
}

output "queue_url" { value = module.stack.queue_url }
output "table_name" { value = module.stack.table_name }
output "function_name" { value = module.stack.function_name }
