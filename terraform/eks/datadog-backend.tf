# Datadog security monitoring backend rules (detection rules that run in the
# Datadog backend, not in the agent). They correlate agent activity events
# (@agent.* fields, data source security_runtime) and generate signals.
#
# Note: these rules use the security monitoring rules API, which requires the
# security_monitoring_rules_write permission on the application key (in
# addition to security_monitoring_cws_agent_rules_write used by the agent
# rules in datadog.tf).

# Correlates multiple cryptomining indicators (miner execution, pool
# connections, persistence setup, system optimization, and IMDSv2 cloud
# credential resolution via the imds_v2_tracking agent rule) within the same
# execution context, per the @process.variables.correlation_key group-by.
resource "datadog_security_monitoring_rule" "cryptomining_attack_chain_detected" {
  case {
    condition     = "miner_execution > 0 && pool_connection > 0 && persistence_setup > 0 && system_optimization > 0"
    name          = "advanced_cryptomining_operation"
    notifications = []
    status        = "critical"
  }
  case {
    condition     = "miner_execution > 0 && pool_connection > 0 && persistence_setup > 0 && cloud_credential_resolution > 0"
    name          = "persistent_cryptomining_imds"
    notifications = []
    status        = "high"
  }
  case {
    condition     = "miner_execution > 0 && pool_connection > 0 && persistence_setup > 0"
    name          = "persistent_cryptomining"
    notifications = []
    status        = "high"
  }
  case {
    condition     = "miner_execution > 0 && pool_connection > 0"
    name          = "active_cryptomining"
    notifications = []
    status        = "medium"
  }
  enabled            = true
  has_extended_title = true
  message            = "## Goal\n\nDetect a complete cryptomining attack chain by correlating multiple indicators of cryptocurrency mining activity within the same execution context.\n\n## Strategy\n\nThis correlation rule identifies cryptomining operations by detecting combinations of the following activity groups:\n\n- **Miner Execution**: Cryptocurrency mining processes identified by their command-line arguments or environment variables (for example, wallet addresses, mining algorithms, pool configurations)\n- **Pool Connection**: Network connections to known mining pool domains or DNS lookups for mining infrastructure\n- **Persistence Setup**: Creation or modification of cron jobs and scheduled tasks to maintain mining operations across reboots\n- **System Optimization**: Modifications to CPU performance settings (MSR writes), cache management, or other system tuning for mining efficiency\n\nThe rule triggers at different severity levels based on the combination of detected activities:\n\n| Case | Severity | Required Components |\n|------|----------|---------------------|\n| Advanced Cryptomining Operation | Critical | Miner + Pool + Persistence + System Optimization |\n| Persistent Cryptomining | High | Miner + Pool + Persistence |\n| Active Cryptomining | Medium | Miner + Pool |\n\n## Triage & Response\n\n1. **Terminate mining processes**: Identify and stop all cryptocurrency mining processes running on the affected system\n\n2. **Block mining pool communications**: Block network access to identified mining pool domains and IP addresses\n\n3. **Isolate affected systems**: Quarantine compromised containers or hosts to prevent lateral spread\n\n4. **Remove persistence mechanisms**: Check for and remove any cron jobs, scheduled tasks, or startup scripts used to maintain mining operations\n\n5. **Analyze mining configuration**: Review process arguments and environment variables for wallet addresses and pool details that may indicate the attacker\n\n6. **Assess resource impact**: Calculate CPU, memory, and network usage consumed by mining processes to estimate financial impact\n\n7. **Investigate initial access**: Determine how the cryptominer was deployed (for example, vulnerable application, compromised credentials, supply chain attack)\n\n8. **Hunt for additional miners**: Search for other systems with similar mining indicators across your environment\n\n9. **Implement preventive controls**: Deploy resource monitoring, network egress filtering for mining pools, and runtime protection to prevent future incidents\n"
  name               = "[CADR] Cryptomining attack chain detected"
  options {
    decrease_criticality_based_on_env = false
    detection_method                  = "threshold"
    evaluation_window                 = 3600
    keep_alive                        = 3600
    max_signal_duration               = 21600
  }
  query {
    aggregation                  = "count"
    data_source                  = "security_runtime"
    group_by_fields              = ["@process.variables.correlation_key", "host", "@container.id"]
    has_optional_group_by_fields = true
    name                         = "miner_execution"
    query                        = "@agent.rule_id:(cryptominer_args OR cryptominer_envs) @process.variables.correlation_key:*"
  }
  query {
    aggregation                  = "count"
    data_source                  = "security_runtime"
    group_by_fields              = ["@process.variables.correlation_key", "host", "@container.id"]
    has_optional_group_by_fields = true
    name                         = "pool_connection"
    query                        = "@agent.rule_id:(mining_pool_domain OR mining_pool_domain_v2 OR mining_pool_lookup) @process.variables.correlation_key:*"
  }
  query {
    aggregation                  = "count"
    data_source                  = "security_runtime"
    group_by_fields              = ["@process.variables.correlation_key", "host", "@container.id"]
    has_optional_group_by_fields = true
    name                         = "persistence_setup"
    query                        = "tactic:ta0003-persistence @process.variables.correlation_key:*"
  }
  query {
    aggregation                  = "count"
    data_source                  = "security_runtime"
    group_by_fields              = ["@process.variables.correlation_key", "host", "@container.id"]
    has_optional_group_by_fields = true
    name                         = "system_optimization"
    query                        = "@agent.rule_id:(kernel_msr_write OR exec_wrmsr OR open_msr_writes OR drop_caches) @process.variables.correlation_key:*"
  }
  query {
    aggregation                  = "count"
    data_source                  = "security_runtime"
    group_by_fields              = ["@process.variables.correlation_key", "host", "@container.id"]
    has_optional_group_by_fields = true
    name                         = "cloud_credential_resolution"
    query                        = "@agent.rule_id:(imds_v2_tracking) @process.variables.correlation_key:*"
  }
  # NOTE: tags may show a diff on the first plan after import but will normalize after the first apply.
  tags = ["agent_platform:linux", "correlation:true", "mitre_platform:linux", "security:attack", "source:runtime-security-agent", "subtechnique:T1496.001-compute-hijacking", "tactic:TA0040-impact", "technique:T1496-resource-hijacking"]
  type = "workload_security"
}

output "cryptomining_attack_chain_rule_id" {
  description = "ID of the [CADR] Cryptomining attack chain detected backend rule"
  value       = datadog_security_monitoring_rule.cryptomining_attack_chain_detected.id
}
