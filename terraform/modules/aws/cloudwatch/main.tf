resource "aws_cloudwatch_log_group" "microservices" {
  name              = "/aws/microservices/${var.name}-${var.environment}"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.kms_key_arn

  tags = merge(
    var.tags,
    {
      Name        = "${var.name}-${var.environment}-logs"
      Environment = var.environment
    }
  )
}

resource "aws_cloudwatch_metric_alarm" "api_high_5xx_errors" {
  alarm_name          = "${var.name}-${var.environment}-high-5xx-error-rate"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = var.alarm_evaluation_periods
  metric_name         = "HTTPCode_Target_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = var.alarm_period_seconds
  statistic           = "Sum"
  threshold           = 10
  alarm_description   = "Alarm triggered when 5XX server errors on API Gateway/ALB exceed threshold"
  alarm_actions       = var.alarm_actions

  tags = merge(
    var.tags,
    {
      Environment = var.environment
    }
  )
}

resource "aws_cloudwatch_metric_alarm" "eks_high_cpu" {
  alarm_name          = "${var.name}-${var.environment}-eks-high-cpu"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = var.alarm_evaluation_periods
  metric_name         = "node_cpu_utilization"
  namespace           = "ContainerInsights"
  period              = var.alarm_period_seconds
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "Alarm triggered when average worker node CPU utilization exceeds 80%"
  alarm_actions       = var.alarm_actions

  dimensions = {
    ClusterName = "${var.name}-${var.environment}"
  }

  tags = merge(
    var.tags,
    {
      Environment = var.environment
    }
  )
}

resource "aws_cloudwatch_dashboard" "this" {
  dashboard_name = "${var.name}-${var.environment}-dashboard"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["AWS/ApplicationELB", "TargetResponseTime", { stat = "Average" }],
            [".", "RequestCount", { stat = "Sum" }]
          ]
          period = 300
          region = "us-east-1"
          title  = "Gateway Throughput & Latency"
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["AWS/ApplicationELB", "HTTPCode_Target_5XX_Count", { stat = "Sum" }],
            [".", "HTTPCode_Target_4XX_Count", { stat = "Sum" }]
          ]
          period = 300
          region = "us-east-1"
          title  = "HTTP Error Signals (4XX / 5XX)"
        }
      }
    ]
  })
}
