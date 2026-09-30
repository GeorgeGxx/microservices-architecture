data "azurerm_subscription" "finops" {}

resource "azurerm_consumption_budget_subscription" "monthly_cost" {
  count           = var.enable_monthly_cost_budget ? 1 : 0
  name            = "${local.name}-${local.env}-monthly-cost"
  subscription_id = data.azurerm_subscription.finops.subscription_id
  amount          = lookup(var.monthly_cost_budget_usd, local.env, 0)
  time_grain      = "Monthly"

  time_period {
    start_date = formatdate("YYYY-MM-01'T'00:00:00Z", timestamp())
    end_date   = "2035-01-01T00:00:00Z"
  }

  filter {
    tag {
      name   = "CostCenter"
      values = ["engineering-${local.env}"]
    }
  }

  dynamic "notification" {
    for_each = { actual = 80, forecasted = 100 }
    content {
      enabled        = true
      operator       = "GreaterThan"
      threshold      = notification.value
      threshold_type = notification.key == "actual" ? "Actual" : "Forecasted"
      contact_emails = var.finops_alert_emails
    }
  }

  lifecycle {
    # Keep the original budget start date; timestamp() advances every month.
    ignore_changes = [time_period[0].start_date]

    precondition {
      condition     = lookup(var.monthly_cost_budget_usd, local.env, 0) > 0
      error_message = "Set monthly_cost_budget_usd for the selected workspace before enabling the Azure budget."
    }
    precondition {
      condition     = length(var.finops_alert_emails) > 0
      error_message = "Set finops_alert_emails before enabling the Azure budget so threshold alerts have recipients."
    }
  }
}
