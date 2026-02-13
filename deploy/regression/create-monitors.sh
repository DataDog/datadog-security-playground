#!/bin/bash
#
# create-monitors.sh - Creates Datadog monitors for detection regression testing.
#
# These monitors alert when the custom metric security.regression.signal_found
# (submitted by verify-signals.sh) indicates that an expected security signal
# was NOT generated after a scenario run.
#
# Required environment variables:
#   DD_API_KEY    - Datadog API key
#   DD_APP_KEY    - Datadog Application key
#
# Optional environment variables:
#   DD_SITE       - Datadog site (default: datadoghq.com)

set -euo pipefail

DD_SITE="${DD_SITE:-datadoghq.com}"
API_URL="https://api.${DD_SITE}/api/v1/monitor"

if [ -z "${DD_API_KEY:-}" ] || [ -z "${DD_APP_KEY:-}" ]; then
  echo "ERROR: DD_API_KEY and DD_APP_KEY environment variables must be set."
  echo ""
  echo "Usage:"
  echo "  export DD_API_KEY=<your-api-key>"
  echo "  export DD_APP_KEY=<your-app-key>"
  echo "  export DD_SITE=datadoghq.com  # optional"
  echo "  $0"
  exit 1
fi

CREATED=0
FAILED=0

create_monitor() {
  local name="$1"
  local body="$2"

  echo -n "Creating monitor: ${name} ... "

  response=$(curl -s -w "\nHTTP_STATUS:%{http_code}" -X POST "${API_URL}" \
    -H "DD-API-KEY: ${DD_API_KEY}" \
    -H "DD-APPLICATION-KEY: ${DD_APP_KEY}" \
    -H "Content-Type: application/json" \
    -d "${body}")

  http_status=$(echo "${response}" | grep "HTTP_STATUS" | cut -d: -f2)
  response_body=$(echo "${response}" | sed '/HTTP_STATUS/d')

  if [ "${http_status}" -eq 200 ] || [ "${http_status}" -eq 201 ]; then
    echo "OK"
    CREATED=$((CREATED + 1))
  else
    echo "FAILED (HTTP ${http_status})"
    echo "  ${response_body}" | head -c 300
    echo ""
    FAILED=$((FAILED + 1))
  fi
}

echo "============================================"
echo "Creating Datadog Regression Monitors"
echo "============================================"
echo "Site: ${DD_SITE}"
echo ""

# Monitor 1: Per-scenario regression monitor
# Alerts when any scenario's signal_found metric drops to 0.
# The verify-signals.sh script submits this metric with scenario tags.
create_monitor \
  "[Detection Regression] Security Signal Missing (per scenario)" \
  '{
    "name": "[Detection Regression] Security Signal Missing",
    "type": "query alert",
    "query": "min(last_12h):min:security.regression.signal_found{env:playground-env} by {scenario} < 1",
    "message": "## Detection Regression Alert\n\nThe expected security signal for scenario **{{scenario.name}}** was not found in the last verification run.\n\nThis indicates a potential detection regression: the attack scenario executed but the Datadog Agent or detection rules did not produce the expected security signal.\n\n### Troubleshooting\n1. Check the scenario-runner CronJob logs: `kubectl logs -n playground -l app=detection-regression`\n2. Check the Datadog Agent health: `kubectl get pods -n datadog`\n3. Review Security Signals Explorer in Datadog\n4. Verify runtime security is enabled on the Agent\n5. Check if detection rule definitions have changed\n\n@slack-security-team",
    "tags": [
      "team:security",
      "env:playground",
      "service:detection-regression"
    ],
    "options": {
      "thresholds": {
        "critical": 1
      },
      "notify_no_data": true,
      "no_data_timeframe": 1440,
      "renotify_interval": 0,
      "include_tags": true,
      "evaluation_delay": 300
    }
  }'

# Monitor 2: RCE correlation signal absence (direct security signal check)
# This is a backup monitor that directly queries for the correlation signal
# via the Events V2 data source.
# NOTE: The query syntax may need adjustment based on your Datadog environment.
# Verify the source and attributes in your Security Signals Explorer first.
create_monitor \
  "[Detection Regression] RCE Correlation Signal Missing" \
  '{
    "name": "[Detection Regression] RCE Correlation Signal Missing",
    "type": "event-v2 alert",
    "query": "events(\"source:security_signals rule_name:\\\"[Execution context] File download and execution activity\\\" cluster_name:playground-cluster\").rollup(\"count\").last(\"12h\") < 1",
    "message": "## RCE Correlation Signal Missing\n\nThe correlation signal **[Execution context] File download and execution activity** has not been seen in the last 12 hours.\n\nThis signal should be generated every 6 hours by the regression CronJob running the rce-malware scenario.\n\n### Troubleshooting\n1. Ensure the correlation rule exists: `assets/correlation/create-rule.sh`\n2. Check CronJob execution: `kubectl get jobs -n playground`\n3. Manually run the scenario: `kubectl exec -it deploy/playground-app -n playground -- /scenarios/rce-malware/detonate.sh --silent`\n\n@slack-security-team",
    "tags": [
      "team:security",
      "env:playground",
      "service:detection-regression",
      "scenario:rce-malware"
    ],
    "options": {
      "thresholds": {
        "critical": 1
      },
      "notify_no_data": true,
      "no_data_timeframe": 1440,
      "renotify_interval": 0
    }
  }'

# Monitor 3: Scenario runner job failure
# Alerts when the CronJob itself fails to execute.
create_monitor \
  "[Detection Regression] Scenario Runner Job Failed" \
  '{
    "name": "[Detection Regression] Scenario Runner Job Failed",
    "type": "event-v2 alert",
    "query": "events(\"source:kubernetes reason:BackOff namespace:playground job_name:detection-regression-runner*\").rollup(\"count\").last(\"12h\") > 0",
    "message": "## Scenario Runner Job Failed\n\nThe detection-regression-runner CronJob in the playground namespace has failed.\n\n### Troubleshooting\n1. Check job status: `kubectl get jobs -n playground -l app=detection-regression`\n2. Check pod logs: `kubectl logs -n playground -l app=detection-regression --tail=100`\n3. Check pod events: `kubectl describe pods -n playground -l app=detection-regression`\n\n@slack-security-team",
    "tags": [
      "team:security",
      "env:playground",
      "service:detection-regression"
    ],
    "options": {
      "thresholds": {
        "critical": 0
      },
      "notify_no_data": false,
      "renotify_interval": 0
    }
  }'

echo ""
echo "============================================"
echo "Done: ${CREATED} created, ${FAILED} failed."
echo "============================================"
echo ""
echo "Note: The event-v2 alert monitor query syntax may need adjustment"
echo "based on how security signals appear in your Datadog environment."
echo "Check Security > Signals Explorer to verify the correct attributes."

if [ "${FAILED}" -gt 0 ]; then
  exit 1
fi
