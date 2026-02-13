#!/bin/bash
#
# run-scenarios.sh - Executes all attack scenarios against the playground app.
#
# This script restarts the playground-app deployment (pulling the latest image),
# waits for readiness, then executes each attack scenario in --silent mode.
#
# Environment variables (all optional):
#   PLAYGROUND_NAMESPACE      - Kubernetes namespace (default: playground)
#   APP_DEPLOYMENT            - Deployment name (default: playground-app)
#   WAIT_AFTER_RESTART        - Seconds to wait after restart for CWS init (default: 60)
#   WAIT_BETWEEN_SCENARIOS    - Seconds between scenario runs (default: 60)

set -uo pipefail

NAMESPACE="${PLAYGROUND_NAMESPACE:-playground}"
DEPLOYMENT="${APP_DEPLOYMENT:-playground-app}"
WAIT_AFTER_RESTART="${WAIT_AFTER_RESTART:-60}"
WAIT_BETWEEN_SCENARIOS="${WAIT_BETWEEN_SCENARIOS:-60}"

PASS=0
FAIL=0
TOTAL=0
START_TS=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

log() { echo "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] $*"; }

# --- Step 1: Restart the playground-app deployment to pull the latest image ---
log "Restarting deployment/${DEPLOYMENT} in namespace ${NAMESPACE}..."
kubectl rollout restart "deployment/${DEPLOYMENT}" -n "${NAMESPACE}"
kubectl rollout status "deployment/${DEPLOYMENT}" -n "${NAMESPACE}" --timeout=300s
log "Deployment restarted successfully."

# --- Step 2: Wait for CWS instrumentation injection and app startup ---
log "Waiting ${WAIT_AFTER_RESTART}s for CWS instrumentation and app startup..."
sleep "${WAIT_AFTER_RESTART}"

# --- Step 3: Resolve the running pod ---
POD=$(kubectl get pod -n "${NAMESPACE}" -l "app=${DEPLOYMENT}" \
  --field-selector=status.phase=Running \
  -o jsonpath='{.items[0].metadata.name}')

if [ -z "${POD}" ]; then
  log "ERROR: No running ${DEPLOYMENT} pod found in namespace ${NAMESPACE}"
  exit 1
fi

log "Using pod: ${POD}"
kubectl wait --for=condition=ready "pod/${POD}" -n "${NAMESPACE}" --timeout=120s

# --- Step 4: Execute scenarios ---
run_scenario() {
  local name="$1"
  shift
  TOTAL=$((TOTAL + 1))
  log "=== Scenario ${TOTAL}: ${name} ==="
  if kubectl exec -n "${NAMESPACE}" "${POD}" -- "$@" 2>&1; then
    PASS=$((PASS + 1))
    log "Scenario '${name}' completed successfully."
  else
    FAIL=$((FAIL + 1))
    log "WARNING: Scenario '${name}' exited with non-zero status."
  fi
  log "Waiting ${WAIT_BETWEEN_SCENARIOS}s before next scenario..."
  sleep "${WAIT_BETWEEN_SCENARIOS}"
}

# Scenario 1: RCE Malware (full attack chain: package install -> download ->
#   binary execution -> cryptominer -> IMDS credential theft -> cloud abuse)
# Expected signals: correlation rule "[Execution context] File download and execution activity"
run_scenario "rce-malware" /scenarios/rce-malware/detonate.sh --silent

# Scenario 2: BPFDoor Network Backdoor (download -> chmod -> persistence -> execute)
# Expected signals: backdoor execution, persistence mechanism, process masquerading
run_scenario "bpfdoor" /scenarios/bpfdoor/detonate.sh --silent

# Scenario 3: PCI DSS 11.5 Findings Generator (chmod, chown, link, rename, open, unlink, utimes)
# Expected findings: pci_11_5_critical_binaries_* agent rules
# Note: requires root - the container must run with securityContext.runAsUser: 0
run_scenario "findings-generator" /scenarios/findings-generator/detonate.sh

# Scenario 4: CoreDump Container Escape (CVE-2022-0492 simulation)
# Expected signals: /proc/sys/kernel/core_pattern write attempt
run_scenario "coredump-escape" /scenarios/coredump-escape-container/detonate.sh

# --- Summary ---
END_TS=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
log "==========================================="
log "Detection regression test run complete."
log "  Started:  ${START_TS}"
log "  Finished: ${END_TS}"
log "  Scenarios: ${TOTAL} total, ${PASS} passed, ${FAIL} failed"
log "==========================================="

if [ "${FAIL}" -gt 0 ]; then
  log "WARNING: ${FAIL} scenario(s) had execution errors. Check logs above."
  exit 1
fi
