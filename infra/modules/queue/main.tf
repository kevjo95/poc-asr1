variable "name" { type = string }
variable "visibility_timeout_seconds" { type = number }
variable "max_receive_count" {
  type    = number
  default = 5
}
variable "retention_seconds" {
  type    = number
  default = 86400
}

resource "aws_sqs_queue" "dlq" {
  name                      = "${var.name}-dlq"
  message_retention_seconds = 1209600
}

resource "aws_sqs_queue" "main" {
  name                       = var.name
  visibility_timeout_seconds = var.visibility_timeout_seconds
  message_retention_seconds  = var.retention_seconds
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq.arn
    maxReceiveCount     = var.max_receive_count
  })
}

# Política mínima para el MS de ingesta: solo SendMessage sobre esta cola.
data "aws_iam_policy_document" "ingest_send" {
  statement {
    actions   = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.main.arn]
  }
}

output "url" { value = aws_sqs_queue.main.url }
output "arn" { value = aws_sqs_queue.main.arn }
output "name" { value = aws_sqs_queue.main.name }
output "dlq_url" { value = aws_sqs_queue.dlq.url }
output "dlq_arn" { value = aws_sqs_queue.dlq.arn }
output "ingest_send_policy_json" { value = data.aws_iam_policy_document.ingest_send.json }
