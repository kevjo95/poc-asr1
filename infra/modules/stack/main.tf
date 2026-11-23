variable "prefix" {
  type    = string
  default = "poc-asr1"
}
variable "reconciler_source_dir" { type = string }
variable "reconciler_timeout_seconds" {
  type    = number
  default = 30
}
variable "reconciler_max_concurrency" {
  type    = number
  default = null
}
variable "simulated_failure_rate" {
  type    = number
  default = 0
}
variable "extra_lambda_environment" {
  type    = map(string)
  default = {}
}

module "queue" {
  source = "../queue"
  name   = "${var.prefix}-ingest"
  # Buena práctica de AWS: visibility timeout >= 6 x timeout de la función.
  visibility_timeout_seconds = var.reconciler_timeout_seconds * 6
}

module "idempotency" {
  source = "../idempotency"
  name   = "${var.prefix}-idempotency"
}

module "reconciler" {
  source                 = "../reconciler"
  name                   = "${var.prefix}-reconciler"
  source_dir             = var.reconciler_source_dir
  queue_arn              = module.queue.arn
  table_name             = module.idempotency.name
  table_arn              = module.idempotency.arn
  timeout_seconds        = var.reconciler_timeout_seconds
  max_concurrency        = var.reconciler_max_concurrency
  simulated_failure_rate = var.simulated_failure_rate
  extra_environment      = var.extra_lambda_environment
}

output "queue_url" { value = module.queue.url }
output "queue_name" { value = module.queue.name }
output "dlq_url" { value = module.queue.dlq_url }
output "table_name" { value = module.idempotency.name }
output "function_name" { value = module.reconciler.function_name }
output "ingest_send_policy_json" { value = module.queue.ingest_send_policy_json }
