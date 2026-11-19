resource "aws_cloudwatch_log_group" "snort" {
  name              = var.log_group_name
  retention_in_days = var.log_retention_days
  tags              = { Name = "${var.project_name}-alerts" }
}

resource "aws_cloudwatch_log_metric_filter" "alerts" {
  name           = "${var.project_name}-lab-alerts"
  log_group_name = aws_cloudwatch_log_group.snort.name
  pattern        = "\"LAB\""
  metric_transformation {
    name          = "SnortAlerts"
    namespace     = var.project_name
    value         = "1"
    default_value = 0
  }
}

resource "aws_cloudwatch_dashboard" "lab" {
  dashboard_name = var.project_name
  dashboard_body = jsonencode({
    widgets = [
      {
        type = "metric", x = 0, y = 0, width = 12, height = 6
        properties = {
          title   = "Snort lab alerts", region = var.aws_region
          metrics = [[var.project_name, "SnortAlerts"]]
          period  = 60, stat = "Sum", view = "timeSeries"
        }
      },
      {
        type = "log", x = 0, y = 6, width = 24, height = 8
        properties = {
          title = "Snort alert_fast", region = var.aws_region
          query = "SOURCE '${aws_cloudwatch_log_group.snort.name}' | fields @timestamp, @message | sort @timestamp desc | limit 100"
          view  = "table"
        }
      }
    ]
  })
}
