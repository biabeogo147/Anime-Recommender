# An email when this project's spend crosses 50% and 100% of the monthly budget (50 and 100 USD by default).
resource "aws_budgets_budget" "monthly" {
  name         = "${var.project}-monthly"
  budget_type  = "COST"
  limit_amount = tostring(var.monthly_budget_usd) # the API takes a string
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  # Only resources tagged project=anime count. The `project` cost-allocation tag is already active in this
  # account for Medical's budget; the same tag key serves both.
  cost_filter {
    name   = "TagKeyValue"
    values = [format("user:project$%s", var.project)] # "$" is a literal here; format() avoids HCL's "$${" escape
  }

  # Spend BEFORE credits. The account's Free plan pays with credit, and the Budgets default nets credits out, so the
  # alerts would see a cost of about zero and never fire while the credit is draining (design §10).
  cost_types {
    include_credit = false
  }

  dynamic "notification" {
    for_each = [50, 100]
    content {
      comparison_operator        = "GREATER_THAN"
      threshold                  = notification.value
      threshold_type             = "PERCENTAGE"
      notification_type          = "ACTUAL" # real spend; FORECASTED would fire on predictions
      subscriber_email_addresses = [var.budget_email]
    }
  }
}
