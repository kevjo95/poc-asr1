# Panel de CloudWatch para la consola de AWS (el video): lo que el dashboard local no ve, medido por AWS.
# Cuesta 0 USD (los 3 primeros paneles con hasta 50 métricas son gratuitos).
locals {
  q   = module.stack.queue_name
  dlq = "${var.name}-ingest-dlq"
  fn  = module.stack.function_name
  w   = { region = var.region, view = "timeSeries", stacked = false, period = 60 }
}

resource "aws_cloudwatch_dashboard" "poc" {
  dashboard_name = var.name
  dashboard_body = jsonencode({
    widgets = [
      { type = "metric", x = 0, y = 0, width = 12, height = 6, properties = merge(local.w, {
        title   = "SQS · mensajes aceptados por minuto (conciliación nivel 1)", stat = "Sum"
        metrics = [["AWS/SQS", "NumberOfMessagesSent", "QueueName", local.q]]
      }) },
      { type = "metric", x = 12, y = 0, width = 12, height = 6, properties = merge(local.w, {
        title = "SQS · cola pendiente y edad del mensaje más viejo", stat = "Maximum"
        metrics = [["AWS/SQS", "ApproximateNumberOfMessagesVisible", "QueueName", local.q],
        ["AWS/SQS", "ApproximateAgeOfOldestMessage", "QueueName", local.q, { yAxis = "right" }]]
      }) },
      { type = "metric", x = 0, y = 6, width = 12, height = 6, properties = merge(local.w, {
        title   = "Lambda de conciliación · invocaciones y errores", stat = "Sum"
        metrics = [["AWS/Lambda", "Invocations", "FunctionName", local.fn], ["AWS/Lambda", "Errors", "FunctionName", local.fn]]
      }) },
      { type = "metric", x = 12, y = 6, width = 6, height = 6, properties = merge(local.w, {
        title   = "DLQ · mensajes (debe ser 0)", stat = "Maximum"
        metrics = [["AWS/SQS", "ApproximateNumberOfMessagesVisible", "QueueName", local.dlq]]
      }) },
      { type = "metric", x = 18, y = 6, width = 6, height = 6, properties = merge(local.w, {
        title   = "DynamoDB · escrituras consumidas", stat = "Sum"
        metrics = [["AWS/DynamoDB", "ConsumedWriteCapacityUnits", "TableName", module.stack.table_name]]
      }) },
    ]
  })
}
