#!/bin/bash
#
# verify-signals.sh - Verifies that expected security signals were generated.
#
# Queries the Datadog Security Signals Search API for each scenario's expected
# signals. Optionally submits a custom metric (security.regression.signal_found)
# so that Datadog monitors can alert on detection regressions.
#
# Required environment variables:
#   DD_API_KEY    - Datadog API key
#   DD_APP_KEY    - Datadog Application key
#
# Optional environment variables:
#   DD_SITE              - Datadog site (default: datadoghq.com)
#   LOOKBACK_MINUTES     - How far back to search for signals (default: 90)
#   SUBMIT_METRICS       - Submit custom metrics to Datadog (default: true)
#   CLUSTER_NAME         - Cluster name tag for signal filtering (default: playground-cluster)

set -uo pipefail

DD_SITE="${DD_SITE:-datadoghq.com}"
LOOKBACK_MINUTES="${LOOKBACK_MINUTES:-90}"
SUBMIT_METRICS="${SUBMIT_METRICS:-true}"
CLUSTER_NAME="${CLUSTER_NAME:-playground-cluster}"

while [ $# -gt 0 ]; do
  case "$1" in
    --lookback)     LOOKBACK_MINUTES="$2"; shift 2 ;;
    --no-metrics)   SUBMIT_METRICS="false"; shift ;;
    --cluster)      CLUSTER_NAME="$2"; shift 2 ;;
    --site)         DD_SITE="$2"; shift 2 ;;
    -h|--help)
      echo "Usage: $0 [--lookback MINUTES] [--no-metrics] [--cluster NAME] [--site SITE]"
      exit 0
      ;;
    *) echo "Unknown argument: $1"; exit 1 ;;
  esac
done

if [ -z "${DD_API_KEY:-}" ] || [ -z "${DD_APP_KEY:-}" ]; then
  echo "ERROR: DD_API_KEY and DD_APP_KEY environment variables must be set."
  exit 1
fi

# Calculate the "from" timestamp
FROM_TS=$(date -u -d "${LOOKBACK_MINUTES} minutes ago" '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null \
  || date -u -v-"${LOOKBACK_MINUTES}"M '+%Y-%m-%dT%H:%M:%SZ')
NOW_EPOCH=$(date +%s)

PASS=0
FAIL=0
TOTAL=0

log() { echo "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] $*"; }

# Submit a custom gauge metric to Datadog
submit_metric() {
  local scenario="$1" value="$2"
  [ "${SUBMIT_METRICS}" != "true" ] && return

  curl -s -X POST "https://api.${DD_SITE}/api/v1/series" \
    -H "DD-API-KEY: ${DD_API_KEY}" \
    -H "Content-Type: application/json" \
    -d "{
      \"series\": [{
        \"metric\": \"security.regression.signal_found\",
        \"points\": [[${NOW_EPOCH}, ${value}]],
        \"type\": \"gauge\",
        \"tags\": [
          \"scenario:${scenario}\",
          \"cluster:${CLUSTER_NAME}\",
          \"env:playground-env\"
        ]
      }]
    }" > /dev/null 2>&1
}

# Query the Security Signals Search API
verify_signal() {
  local name="$1"
  local scenario_tag="$2"
  local query="$3"

  TOTAL=$((TOTAL + 1))
  log "Checking: ${name} ..."

  # Build JSON body safely: escape double quotes in query
  local escaped_query
  escaped_query=$(printf '%s' "${query}" | sed 's/"/\\"/g')

  local response
  response=$(curl -s -X POST "https://api.${DD_SITE}/api/v2/security_monitoring/signals/search" \
    -H "DD-API-KEY: ${DD_API_KEY}" \
    -H "DD-APPLICATION-KEY: ${DD_APP_KEY}" \
    -H "Content-Type: application/json" \
    -d "{\"filter\":{\"query\":\"${escaped_query}\",\"from\":\"${FROM_TS}\",\"to\":\"now\"},\"page\":{\"limit\":1}}")

  # Check for API errors
  if echo "${response}" | grep -q '"errors"'; then
    log "  ERROR: API returned an error."
    log "  Response: $(echo "${response}" | head -c 300)"
    FAIL=$((FAIL + 1))
    submit_metric "${scenario_tag}" 0
    return 1
  fi

  # Extract total_count (use jq if available, otherwise grep)
  local total=0
  if command -v jq > /dev/null 2>&1; then
    total=$(echo "${response}" | jq -r '.meta.page.total_count // 0')
  else
    total=$(echo "${response}" | grep -o '"total_count":[0-9]*' | head -1 | cut -d: -f2)
    total="${total:-0}"
  fi

  if [ "${total}" -gt 0 ]; then
    log "  PASS: ${total} signal(s) found."
    PASS=$((PASS + 1))
    submit_metric "${scenario_tag}" 1
    return 0
  else
    log "  FAIL: No signals found."
    FAIL=$((FAIL + 1))
    submit_metric "${scenario_tag}" 0
    return 1
  fi
}

log "============================================"
log "Detection Regression - Signal Verification"
log "============================================"
log "Datadog site:  ${DD_SITE}"
log "Cluster:       ${CLUSTER_NAME}"
log "Lookback:      ${LOOKBACK_MINUTES} minutes (from ${FROM_TS})"
log "Submit metrics: ${SUBMIT_METRICS}"
log ""

# --- Scenario 1: RCE Malware ---
# The correlation rule groups 5 event types into a single critical signal.
# This is the most reliable signal to verify.
verify_signal \
  "RCE Malware - Correlation Signal (Critical)" \
  "rce-malware" \
  "rule.name:\"[Execution context] File download and execution activity\"" \
  || true

# --- Scenario 2: BPFDoor ---
# BPFDoor triggers workload security signals for backdoor process execution
# and persistence. The exact rule names depend on your Datadog environment's
# built-in detection rules. Adjust the query if needed.
verify_signal \
  "BPFDoor - Workload Security Signals" \
  "bpfdoor" \
  "type:workload_security service:playground-app" \
  || true

# --- Scenario 3: Findings Generator (PCI DSS 11.5) ---
# Findings are stored separately from signals. This query checks for related
# workload security signals triggered by critical binary modifications.
# Note: You may also want to query the CSM Findings API for compliance findings.
verify_signal \
  "Findings Generator - Binary Modification Signals" \
  "findings-generator" \
  "type:workload_security @agent.rule_id:pci_11_5*" \
  || true

# --- Scenario 4: CoreDump Container Escape ---
# Checks for signals related to /proc/sys/kernel/core_pattern write attempts.
verify_signal \
  "CoreDump Escape - Container Escape Attempt" \
  "coredump-escape" \
  "type:workload_security service:playground-app core_pattern" \
  || true

# --- Results ---
log ""
log "============================================"
log "Verification Results: ${PASS}/${TOTAL} passed, ${FAIL}/${TOTAL} failed"
log "============================================"

if [ "${FAIL}" -gt 0 ]; then
  log ""
  log "DETECTION REGRESSION DETECTED!"
  log ""
  log "Troubleshooting steps:"
  log "  1. Verify the Datadog Agent is running: kubectl get pods -n datadog"
  log "  2. Check runtime security is enabled: kubectl logs -n datadog -l app=datadog -c security-agent"
  log "  3. Review signals in Datadog: Security > Signals Explorer"
  log "  4. Increase --lookback if signal propagation is slow"
  log "  5. Adjust signal queries to match your environment's rule names"
  exit 1
fi
