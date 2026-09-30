resource "aws_budgets_budget" "monthly_cost" {
  count        = var.enable_monthly_cost_budget ? 1 : 0
  name         = "${local.name}-${local.env}-monthly-cost"
  budget_type  = "COST"
  limit_amount = tostring(lookup(var.monthly_cost_budget_usd, local.env, 0))
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  cost_filter {
    name   = "TagKeyValue"
    values = ["user:CostCenter$engineering-${local.env}"]
  }

  dynamic "notification" {
    for_each = var.finops_alert_emails
    content {
      comparison_operator        = "GREATER_THAN"
      threshold                  = 80
      threshold_type             = "PERCENTAGE"
      notification_type          = "ACTUAL"
      subscriber_email_addresses = [notification.value]
    }
  }

  dynamic "notification" {
    for_each = var.finops_alert_emails
    content {
      comparison_operator        = "GREATER_THAN"
      threshold                  = 100
      threshold_type             = "PERCENTAGE"
      notification_type          = "FORECASTED"
      subscriber_email_addresses = [notification.value]
    }
  }

  lifecycle {
    precondition {
      condition     = lookup(var.monthly_cost_budget_usd, local.env, 0) > 0
      error_message = "Set monthly_cost_budget_usd for the selected workspace before enabling the AWS budget."
    }
    precondition {
      condition     = length(var.finops_alert_emails) > 0
      error_message = "Set finops_alert_emails before enabling the AWS budget so threshold alerts have recipients."
    }
  }
}
