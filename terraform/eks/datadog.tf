# Datadog resources. The API key can be the same one the agent uses; the app
# key needs the permissions listed in the README.

provider "datadog" {
  api_key = var.datadog_api_key
  app_key = var.datadog_app_key
  api_url = "https://api.${var.datadog_site}"
}

# Scoped to the playground agents: env:playground-env, from DD_ENV in deploy/datadog-agent.yaml.
resource "datadog_csm_threats_policy" "cadr_imdsv2_tracking" {
  count = var.enable_cadr_rules ? 1 : 0

  name            = "[CADR] IMDSv2 tracking"
  description     = "Policy for the imds_v2_tracking agent rule"
  enabled         = true
  host_tags_lists = [["env:playground-env"]]
}

# Consumed by the cryptomining backend rule via @agent.rule_id:imds_v2_tracking.
resource "datadog_csm_threats_agent_rule" "imds_v2_tracking" {
  count = var.enable_cadr_rules ? 1 : 0

  name       = "imds_v2_tracking"
  policy_id  = datadog_csm_threats_policy.cadr_imdsv2_tracking[0].id
  enabled    = true
  expression = "imds.aws.is_imds_v2 == true && imds.type == \"response\" && imds.aws.security_credentials.type == \"AWS-HMAC\""

  description = "IMDSv2 responses carrying AWS HMAC credentials, for backend correlation"

  product_tags = [
    "tactic:TA0006-credential-access",
    "technique:T1552-unsecured-credentials",
    "subtechnique:T1552.005-cloud-instance-metadata-api",
  ]
}

# -----------------------------------------------------------------------------
# Langflow blocking policy
#
# Blocking (kill) clones of the default detection rules used by the
# langflow-rce scenario. The Terraform provider (v4.32.0) does not support
# kill actions — actions.kill / disable_container_disarmer /
# disable_executable_disarmer are not exposed in the resource schema — so the
# kill action on each rule is added manually via the API (UI or PATCH
# /api/v2/cloud_workload_security/agent_rules) after this is applied.
#
# CAVEAT: the provider always sends the `actions` attribute on create and
# update, and an empty list removes all actions. Any `terraform apply` that
# modifies these rules will therefore wipe the manually-added kill actions;
# re-add them after applying.
#
# The kill actions only take effect because the two runtime-security disarmers
# are disabled in deploy/datadog-agent.yaml
# (DD_RUNTIME_SECURITY_CONFIG_ENFORCEMENT_DISARMER_{CONTAINER,EXECUTABLE}_ENABLED=false);
# with them enabled (the agent default), kill actions are silently disarmed and
# the rules only detect.
# -----------------------------------------------------------------------------

# Scoped to the playground agents: env:playground-env, from DD_ENV in
# deploy/datadog-agent.yaml.
resource "datadog_csm_threats_policy" "langflow_blocking" {
  name            = "langflow-blocking"
  description     = "Blocking (kill) clones of the default container rules, used by the langflow-rce scenario"
  enabled         = true
  host_tags_lists = [["env:playground-env"]]
}

resource "datadog_csm_threats_agent_rule" "package_management_in_container_v2_blocking" {
  name       = "package_management_in_container_v2_blocking"
  policy_id  = datadog_csm_threats_policy.langflow_blocking.id
  enabled    = true
  expression = "exec.file.path in [~\"/usr/bin/apt*\", \"/usr/bin/dpkg\", \"/usr/bin/rpm\", \"/usr/bin/unattended-upgrade\", \"/usr/bin/npm\", ~\"/usr/bin/pip*\", ~\"/usr/local/bin/pip*\", \"/usr/bin/yum\", \"/usr/bin/dnf-3\", \"/usr/bin/dnf4\", \"/usr/bin/dnf-automatic\", \"/sbin/apk\", \"/usr/lib/snapd/snapd\"] && process.container.id != \"\" "

  # kill action added manually via the API — see the note above
}

resource "datadog_csm_threats_agent_rule" "new_binary_execution_in_container_v2_blocking" {
  name       = "new_binary_execution_in_container_v2_blocking"
  policy_id  = datadog_csm_threats_policy.langflow_blocking.id
  enabled    = true
  expression = "process.container.id != \"\" && process.file.in_upper_layer && process.file.modification_time < 30s && exec.file.name != \"\" "

  # kill action added manually via the API — see the note above
}

resource "datadog_csm_threats_agent_rule" "tty_shell_in_container_blocking" {
  name       = "tty_shell_in_container_blocking"
  policy_id  = datadog_csm_threats_policy.langflow_blocking.id
  enabled    = true
  expression = <<-EOF
  exec.file.path in [ "/bin/dash",
    "/usr/bin/dash",
    "/bin/sh",
    "/bin/static-sh",
    "/usr/bin/sh",
    "/bin/bash",
    "/usr/bin/bash",
    "/bin/bash-static",
    "/usr/bin/zsh",
    "/usr/bin/ash",
    "/usr/bin/csh",
    "/usr/bin/ksh",
    "/usr/bin/tcsh",
    "/usr/lib/initramfs-tools/bin/busybox",
    "/bin/busybox",
    "/usr/bin/fish",
    "/bin/ksh93",
    "/bin/rksh",
    "/bin/rksh93",
    "/bin/lksh",
    "/bin/mksh",
    "/bin/mksh-static",
    "/usr/bin/csharp",
    "/bin/posh",
    "/usr/bin/rc",
    "/bin/sash",
    "/usr/bin/yash",
    "/bin/zsh5",
    "/bin/zsh5-static" ] && process.tty_name != "" && process.container.id != ""
  EOF

  # kill action added manually via the API — see the note above
}

resource "datadog_csm_threats_agent_rule" "cryptominer_args_blocking" {
  name       = "cryptominer_args_blocking"
  policy_id  = datadog_csm_threats_policy.langflow_blocking.id
  enabled    = true
  expression = "exec.args_options in [~\"cpu-priority*\", ~\"donate-level*\", ~\"wallet-address*\"] || exec.args_flags == \"randomx-1gb-pages\" || exec.args in [~\"*stratum+tcp*\", ~\"*stratum+ssl*\", ~\"*stratum1+tcp*\", ~\"*stratum1+ssl*\", ~\"*stratum2+tcp*\", ~\"*stratum2+ssl*\", ~\"*nicehash*\", ~\"*yespower*\"]"

  # kill action added manually via the API — see the note above
}

output "langflow_blocking_policy_id" {
  value = datadog_csm_threats_policy.langflow_blocking.id
}

output "langflow_blocking_agent_rule_ids" {
  value = {
    "package_management_in_container_v2_blocking"   = datadog_csm_threats_agent_rule.package_management_in_container_v2_blocking.id
    "new_binary_execution_in_container_v2_blocking" = datadog_csm_threats_agent_rule.new_binary_execution_in_container_v2_blocking.id
    "tty_shell_in_container_blocking"               = datadog_csm_threats_agent_rule.tty_shell_in_container_blocking.id
    "cryptominer_args_blocking"                     = datadog_csm_threats_agent_rule.cryptominer_args_blocking.id
  }
}

# Keeps rules created before enable_cadr_rules existed instead of replacing them.
moved {
  from = datadog_csm_threats_policy.cadr_imdsv2_tracking
  to   = datadog_csm_threats_policy.cadr_imdsv2_tracking[0]
}

moved {
  from = datadog_csm_threats_agent_rule.imds_v2_tracking
  to   = datadog_csm_threats_agent_rule.imds_v2_tracking[0]
}

output "cadr_imdsv2_tracking_policy_id" {
  value = try(datadog_csm_threats_policy.cadr_imdsv2_tracking[0].id, null)
}

output "imds_v2_tracking_rule_id" {
  value = try(datadog_csm_threats_agent_rule.imds_v2_tracking[0].id, null)
}
