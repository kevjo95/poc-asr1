variable "name" { type = string }
variable "source_dir" { type = string }
variable "queue_arn" { type = string }
variable "table_name" { type = string }
variable "table_arn" { type = string }
variable "timeout_seconds" { type = number }
variable "memory_mb" {
  type    = number
  default = 256
}
variable "batch_size" {
  type    = number
  default = 10
}
variable "max_concurrency" {
  type        = number
  default     = null
  description = "Concurrencia máxima del mapping de SQS (>= 2). null = sin límite."
}
variable "processing_ttl_seconds" {
  type    = number
  default = 60
}
variable "simulated_failure_rate" {
  type        = number
  default     = 0
  description = "Fracción de eventos que fallan tras marcarlos EN_PROCESO (ASR2 modela 0.01)."
}
variable "extra_environment" {
  type    = map(string)
  default = {}
}

data "archive_file" "zip" {
  type        = "zip"
  source_dir  = var.source_dir
  output_path = "${path.module}/.build/${var.name}.zip"
  excludes    = ["tests", "__pycache__", "requirements-dev.txt"]
}

data "aws_iam_policy_document" "assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "this" {
  name               = "${var.name}-role"
  assume_role_policy = data.aws_iam_policy_document.assume.json
}

data "aws_iam_policy_document" "perms" {
  statement {
    actions   = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes"]
    resources = [var.queue_arn]
  }
  statement {
    actions   = ["dynamodb:PutItem", "dynamodb:UpdateItem", "dynamodb:GetItem"]
    resources = [var.table_arn]
  }
  statement {
    actions   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "this" {
  name   = "${var.name}-policy"
  role   = aws_iam_role.this.id
  policy = data.aws_iam_policy_document.perms.json
}

resource "aws_lambda_function" "this" {
  function_name    = var.name
  role             = aws_iam_role.this.arn
  runtime          = "python3.12"
  handler          = "handler.handler"
  filename         = data.archive_file.zip.output_path
  source_code_hash = data.archive_file.zip.output_base64sha256
  timeout          = var.timeout_seconds
  memory_size      = var.memory_mb

  environment {
    variables = merge({
      TABLE_NAME             = var.table_name
      PROCESSING_TTL_SECONDS = tostring(var.processing_ttl_seconds)
      SIMULATED_FAILURE_RATE = tostring(var.simulated_failure_rate)
    }, var.extra_environment)
  }
}

resource "aws_lambda_event_source_mapping" "sqs" {
  event_source_arn        = var.queue_arn
  function_name           = aws_lambda_function.this.arn
  batch_size              = var.batch_size
  function_response_types = ["ReportBatchItemFailures"]

  dynamic "scaling_config" {
    for_each = var.max_concurrency == null ? [] : [var.max_concurrency]
    content {
      maximum_concurrency = scaling_config.value
    }
  }
}

output "function_name" { value = aws_lambda_function.this.function_name }
output "function_arn" { value = aws_lambda_function.this.arn }
