# Empty secrets: Terraform creates the names and nothing else. Values are written once from the workstation with
#   aws secretsmanager put-secret-value --secret-id anime/<name> --secret-string file://...
# so they never enter Git or Terraform state (docs/terraform/guide.md, step 2).
#
#   anime/llm        {"GOOGLE_API_KEY": "...", "HF_TOKEN": "..."}        read by External Secrets
#   anime/langfuse   {"LANGFUSE_PUBLIC_KEY": "...", "LANGFUSE_SECRET_KEY": "..."}   read by External Secrets
#   anime/alerting   {"DISCORD_WEBHOOK_URL": "..."}                      read by External Secrets
#   anime/wireguard  {"serverPrivateKey": "...", "operatorPublicKey": "..."}  read by the gateway ONLY
resource "aws_secretsmanager_secret" "this" {
  for_each = toset(["llm", "langfuse", "alerting", "wireguard"])

  name = "${var.project}/${each.key}"

  # A deleted secret stays restorable for 7 days — which is also why the same name cannot be reused at once.
  recovery_window_in_days = 7
}

# The cluster stack names the three External Secrets may read by ARN, never by `anime/*`: a wildcard would also
# cover anime/wireguard, handing a controller inside the cluster the key to the tunnel into it (Terraform A5.4).
output "external_secrets_arns" {
  value = [for k in ["llm", "langfuse", "alerting"] : aws_secretsmanager_secret.this[k].arn]
}
