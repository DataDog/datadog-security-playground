#!/bin/bash
#
# setup.sh - One-time setup for the detection regression testing infrastructure.
#
# This script:
#   1. Verifies prerequisites
#   2. Patches the playground-app deployment to run as root (required by findings-generator)
#   3. Creates the ConfigMap with runner/verifier scripts
#   4. Applies RBAC resources
#   5. Applies CronJob manifests
#   6. Creates the correlation detection rule in Datadog (for the RCE scenario)
#   7. Creates Datadog monitors
#
# Required environment variables:
#   DD_API_KEY    - Datadog API key
#   DD_APP_KEY    - Datadog Application key
#
# Optional environment variables:
#   DD_SITE                   - Datadog site (default: datadoghq.com)
#   DD_API_SITE               - Alias for DD_SITE (for compatibility with create-rule.sh)
#   PLAYGROUND_NAMESPACE      - Namespace for the playground app (default: playground)
#   DATADOG_NAMESPACE         - Namespace for the Datadog agent (default: datadog)
#   SKIP_MONITORS             - Set to "true" to skip monitor creation
#   SKIP_CORRELATION_RULE     - Set to "true" to skip correlation rule creation

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

DD_SITE="${DD_SITE:-datadoghq.com}"
DD_API_SITE="${DD_API_SITE:-${DD_SITE}}"
PLAYGROUND_NS="${PLAYGROUND_NAMESPACE:-playground}"
DATADOG_NS="${DATADOG_NAMESPACE:-datadog}"
SKIP_MONITORS="${SKIP_MONITORS:-false}"
SKIP_CORRELATION_RULE="${SKIP_CORRELATION_RULE:-false}"

log() { echo "[setup] $*"; }
err() { echo "[setup] ERROR: $*" >&2; }

# --- Preflight checks ---
log "Running preflight checks..."

if ! command -v kubectl > /dev/null 2>&1; then
  err "kubectl is not installed or not in PATH."
  exit 1
fi

if ! kubectl cluster-info > /dev/null 2>&1; then
  err "Cannot connect to Kubernetes cluster. Check your kubeconfig."
  exit 1
fi

if [ -z "${DD_API_KEY:-}" ] || [ -z "${DD_APP_KEY:-}" ]; then
  err "DD_API_KEY and DD_APP_KEY must be set."
  echo ""
  echo "Usage:"
  echo "  export DD_API_KEY=<your-datadog-api-key>"
  echo "  export DD_APP_KEY=<your-datadog-application-key>"
  echo "  export DD_SITE=datadoghq.com  # optional"
  echo "  $0"
  exit 1
fi

# Verify namespaces exist
for ns in "${PLAYGROUND_NS}" "${DATADOG_NS}"; do
  if ! kubectl get namespace "${ns}" > /dev/null 2>&1; then
    log "Creating namespace: ${ns}"
    kubectl create namespace "${ns}"
  fi
done

# --- Step 1: Create secrets for the verifier CronJob ---
log "Creating/updating secrets in namespace ${PLAYGROUND_NS}..."

kubectl create secret generic datadog-regression-keys \
  --namespace "${PLAYGROUND_NS}" \
  --from-literal=api-key="${DD_API_KEY}" \
  --from-literal=app-key="${DD_APP_KEY}" \
  --dry-run=client -o yaml | kubectl apply -f -

# --- Step 2: Patch playground-app to run as root ---
# The findings-generator scenario requires root privileges (checks $EUID == 0).
# This patch sets runAsUser: 0 on the playground-app container.
log "Patching playground-app deployment to run as root..."

kubectl patch deployment playground-app \
  --namespace "${PLAYGROUND_NS}" \
  --type=json \
  -p='[{"op":"add","path":"/spec/template/spec/containers/0/securityContext","value":{"runAsUser":0}}]' \
  2>/dev/null || log "Deployment not found yet or already patched. Will be applied when app is deployed."

# --- Step 3: Create ConfigMap with scripts ---
log "Creating ConfigMap with runner and verifier scripts..."

kubectl create configmap scenario-runner-scripts \
  --namespace "${PLAYGROUND_NS}" \
  --from-file=run-scenarios.sh="${SCRIPT_DIR}/run-scenarios.sh" \
  --from-file=verify-signals.sh="${SCRIPT_DIR}/verify-signals.sh" \
  --dry-run=client -o yaml | kubectl apply -f -

# --- Step 4: Apply RBAC ---
log "Applying RBAC resources..."
kubectl apply -f "${SCRIPT_DIR}/rbac.yaml"

# --- Step 5: Apply CronJobs ---
log "Applying CronJob manifests..."
kubectl apply -f "${SCRIPT_DIR}/cronjob.yaml"

# --- Step 6: Create correlation detection rule ---
if [ "${SKIP_CORRELATION_RULE}" = "true" ]; then
  log "Skipping correlation rule creation (SKIP_CORRELATION_RULE=true)."
else
  log "Creating correlation detection rule in Datadog..."
  export DD_API_KEY DD_APP_KEY DD_API_SITE
  if bash "${REPO_ROOT}/assets/correlation/create-rule.sh"; then
    log "Correlation rule created successfully."
  else
    log "WARNING: Correlation rule creation failed. It may already exist."
    log "You can create it manually: DD_API_KEY=... DD_APP_KEY=... DD_API_SITE=... assets/correlation/create-rule.sh"
  fi
fi

# --- Step 7: Create monitors ---
if [ "${SKIP_MONITORS}" = "true" ]; then
  log "Skipping monitor creation (SKIP_MONITORS=true)."
else
  log "Creating Datadog monitors..."
  export DD_API_KEY DD_APP_KEY DD_SITE
  bash "${SCRIPT_DIR}/create-monitors.sh" || log "WARNING: Some monitors failed to create. Check output above."
fi

# --- Done ---
echo ""
log "============================================"
log "Setup complete!"
log "============================================"
echo ""
echo "The following resources were created:"
echo "  - Secret:     datadog-regression-keys (namespace: ${PLAYGROUND_NS})"
echo "  - ConfigMap:  scenario-runner-scripts (namespace: ${PLAYGROUND_NS})"
echo "  - RBAC:       scenario-runner ServiceAccount, Role, RoleBinding"
echo "  - CronJob:    detection-regression-runner (schedule: 0 */6 * * *)"
echo "  - CronJob:    detection-regression-verifier (schedule: 30 */6 * * *)"
echo ""
echo "To trigger a test run immediately:"
echo "  kubectl create job --from=cronjob/detection-regression-runner manual-test-\$(date +%s) -n ${PLAYGROUND_NS}"
echo ""
echo "To check CronJob status:"
echo "  kubectl get cronjobs -n ${PLAYGROUND_NS} -l app=detection-regression"
echo ""
echo "To view job logs:"
echo "  kubectl logs -n ${PLAYGROUND_NS} -l app=detection-regression --tail=100"
echo ""
echo "To upgrade the Datadog Agent to the latest version:"
echo "  helm repo update && helm upgrade datadog-agent datadog/datadog -n ${DATADOG_NS} -f deploy/datadog-agent.yaml"
