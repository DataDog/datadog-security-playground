# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0

# An SSM document that loads a local CWS policy file onto the instance.
#
# Run Command sends commands, not files, so the policy travels inline as a
# base64 document parameter. Run Command has no per-parameter size quota; the
# binding limit is 64 KB per document, and a base64-encoded policy is about a
# third larger than the file. That is ample for hand-written policies. If you
# ever exceed it, stage the file in S3 and fetch it here instead.
#
# ./load-policy.sh wraps this so you can pass a path instead of encoding by hand.

resource "aws_ssm_document" "load_cws_policy" {
  name            = "${local.name}-load-cws-policy"
  document_type   = "Command"
  document_format = "YAML"

  content = yamlencode({
    schemaVersion = "2.2"
    description   = "Load a Workload Protection policy file into the Datadog Agent and reload the rules"

    parameters = {
      policyName = {
        type        = "String"
        description = "Policy file name. Must end in .policy for the agent to load it."
        # Filename lands in a shell command, so keep it to safe characters.
        allowedPattern = "^[a-zA-Z0-9._-]+\\.policy$"
      }
      policyContent = {
        type        = "String"
        description = "Base64-encoded contents of the policy file"
      }
      logLevel = {
        type           = "String"
        description    = "Agent log level to set before loading, since policy errors are only visible at debug"
        default        = "debug"
        allowedPattern = "^[a-z]+$"
      }
    }

    mainSteps = [
      {
        action = "aws:runShellScript"
        name   = "loadPolicy"
        inputs = {
          # aws:runShellScript executes this under /bin/sh, which is dash on
          # Ubuntu, so it must stay POSIX: no pipefail. `set -e` still fails the
          # command on the first bad step rather than reporting success after a
          # rejected policy, and the decode is checked explicitly below since
          # without pipefail a failing base64 would leave an empty file that
          # `docker cp` would happily copy.
          runCommand = [
            "set -eu",
            "policy_path=\"/tmp/{{policyName}}\"",
            "trap 'rm -f \"$policy_path\"' EXIT",
            "printf '%s' '{{policyContent}}' | base64 -d > \"$policy_path\"",
            "[ -s \"$policy_path\" ] || { echo 'decoded policy file is empty' >&2; exit 1; }",
            "docker exec ${local.agent_container} agent config set log_level '{{logLevel}}'",
            "docker cp \"$policy_path\" ${local.agent_container}:/etc/datadog-agent/runtime-security.d/",
            "docker exec ${local.agent_container} system-probe runtime policy check",
            "docker exec ${local.agent_container} system-probe runtime policy reload",
            "docker exec ${local.agent_container} security-agent status",
          ]
        }
      }
    ]
  })
}
