# Datadog resources. The API key can be the same one the agent uses; the app
# key needs the permissions listed in the README.

provider "datadog" {
  api_key = var.datadog_api_key
  app_key = var.datadog_app_key
  api_url = "https://api.${var.datadog_site}"
}

# Scoped to the playground agents: env:playground-env, from DD_ENV in deploy/datadog-agent.yaml.
resource "datadog_csm_threats_policy" "cadr_imdsv2_tracking" {
  name            = "[CADR] IMDSv2 tracking"
  description     = "Policy for the imds_v2_tracking agent rule"
  enabled         = true
  host_tags_lists = [["env:playground-env"]]
}

# Consumed by the cryptomining backend rule via @agent.rule_id:imds_v2_tracking.
resource "datadog_csm_threats_agent_rule" "imds_v2_tracking" {
  name       = "imds_v2_tracking"
  policy_id  = datadog_csm_threats_policy.cadr_imdsv2_tracking.id
  enabled    = true
  expression = "imds.aws.is_imds_v2 == true && imds.type == \"response\" && imds.aws.security_credentials.type == \"AWS-HMAC\""

  description = "IMDSv2 responses carrying AWS HMAC credentials, for backend correlation"

  product_tags = [
    "tactic:TA0006-credential-access",
    "technique:T1552-unsecured-credentials",
    "subtechnique:T1552.005-cloud-instance-metadata-api",
  ]
}

output "cadr_imdsv2_tracking_policy_id" {
  value = datadog_csm_threats_policy.cadr_imdsv2_tracking.id
}

output "imds_v2_tracking_rule_id" {
  value = datadog_csm_threats_agent_rule.imds_v2_tracking.id
}
