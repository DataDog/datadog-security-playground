# Datadog resources managed via the Datadog provider.
#
# Authentication: the API key can be the same one the agent uses
# (var.datadog_api_key); an application key (var.datadog_app_key) is
# additionally required to manage Datadog resources through the provider.

provider "datadog" {
  api_key = var.datadog_api_key
  app_key = var.datadog_app_key
  api_url = "https://api.${var.datadog_site}"
}

# The helm-deployed agent uses the org's default CSM Threats policy, so the
# rule must be attached to (and enabled in) that policy to actually run.
data "datadog_csm_threats_policies" "all" {}

locals {
  default_csm_policy_id = one([for p in data.datadog_csm_threats_policies.all.policies : p.id if p.name == var.csm_default_policy_name])
}

# Mirrors security-monitoring/workload-security/agent-rules/linux/network/imds_host_aws_access_key_ids.yaml
#
# Not carried over from the YAML: priority, osFilter, agentConstraint, category
# and defaultRuleId are not part of the agent-rule create/update API used by
# the provider — the rule behavior lives in `expression` + `actions`.
resource "datadog_csm_threats_agent_rule" "imds_host_aws_access_key_ids" {
  name       = "imds_host_aws_access_key_ids"
  policy_id  = local.default_csm_policy_id
  enabled    = true
  silent     = true
  expression = "imds.type == \"response\" && imds.cloud_provider == \"aws\" && imds.aws.security_credentials.access_key_id != \"\""

  description = "Track the AWS access key IDs a host resolved from IMDS to correlate its activity with Cloud SIEM and CloudTrail"

  product_tags = [
    "tactic:TA0006-credential-access",
    "technique:T1552-unsecured-credentials",
    "subtechnique:T1552.005-cloud-instance-metadata-api",
    "policy:threat-detection",
  ]

  actions {
    set {
      name   = "host_aws_access_key_ids"
      field  = "imds.aws.security_credentials.access_key_id"
      append = true
      size   = 10
      ttl    = 43200000000000 # 12h, expressed in nanoseconds
    }
  }
}

output "csm_default_policy_id" {
  description = "ID of the default CSM Threats agent policy"
  value       = local.default_csm_policy_id
}

output "imds_host_aws_access_key_ids_rule_id" {
  description = "ID of the imds_host_aws_access_key_ids agent rule"
  value       = datadog_csm_threats_agent_rule.imds_host_aws_access_key_ids.id
}
