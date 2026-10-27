#!/usr/bin/env bash
# Load a local Workload Protection policy file onto the playground instance.
#
# Replaces the local `docker cp` workflow: the file is base64-encoded, sent as an
# SSM document parameter, and applied on the host. Run from this directory, after
# `terraform apply`.
#
#   ./load-policy.sh my-rules.policy
set -euo pipefail

policy_file=${1:-}

if [ -z "$policy_file" ] || [ ! -f "$policy_file" ]; then
  echo "usage: $0 <policy-file>" >&2
  exit 1
fi

policy_name=$(basename "$policy_file")

case "$policy_name" in
  *.policy) ;;
  *)
    echo "error: the agent only loads files ending in .policy (got '$policy_name')" >&2
    exit 1
    ;;
esac

region=$(terraform output -raw region)
instance=$(terraform output -raw instance_id)
document=$(terraform output -raw load_policy_document_name)

# tr -d '\n' because GNU base64 wraps at 76 columns.
content=$(base64 < "$policy_file" | tr -d '\n')

# Built as JSON rather than key=value shorthand, so base64 padding and any
# punctuation in the file name cannot confuse the parser.
params=$(printf '{"policyName":["%s"],"policyContent":["%s"]}' "$policy_name" "$content")

command_id=$(aws ssm send-command \
  --region "$region" \
  --instance-ids "$instance" \
  --document-name "$document" \
  --parameters "$params" \
  --query Command.CommandId \
  --output text)

echo "sent $policy_name to $instance (command $command_id)"

# Returns non-zero when the command fails; the output below is what explains why.
aws ssm wait command-executed \
  --region "$region" \
  --command-id "$command_id" \
  --instance-id "$instance" || true

aws ssm get-command-invocation \
  --region "$region" \
  --command-id "$command_id" \
  --instance-id "$instance" \
  --query '[Status, StandardOutputContent, StandardErrorContent]' \
  --output text
