# Detection Regression Testing - Plan & Implementation

Periodically deploy the latest playground app and Datadog Agent images in an
existing EKS cluster, run all attack scenarios, and verify that expected
security signals continue to be produced.

---

## Architecture

```
Every 6h at :00                          Every 6h at :30
┌──────────────────────┐                 ┌──────────────────────┐
│  CronJob: runner     │                 │  CronJob: verifier   │
│                      │                 │                      │
│  1. rollout restart  │   30 min gap    │  1. Query DD Signals │
│  2. wait for CWS     │ ─────────────→  │     Search API       │
│  3. run 4 scenarios  │   (propagation) │  2. Submit metrics   │
│  4. log results      │                 │  3. Report pass/fail │
└──────────┬───────────┘                 └──────────┬───────────┘
           │                                        │
           ▼                                        ▼
   DD Agent captures                    DD custom metric:
   security events →                    security.regression.
   signals/findings                     signal_found{scenario:X}
                                                    │
                                                    ▼
                                        ┌───────────────────────┐
                                        │   Datadog Monitors    │
                                        │                       │
                                        │  metric < 1 → ALERT  │
                                        │  (regression detected)│
                                        └───────────────────────┘
```

---

## Files

| File | Purpose |
|---|---|
| `rbac.yaml` | ServiceAccount, Role, and RoleBinding granting the CronJob permission to restart deployments, list pods, and exec into pods in the `playground` namespace |
| `run-scenarios.sh` | Orchestrator script that restarts the playground-app deployment (pulling the latest image), waits for CWS instrumentation, then executes all 4 scenarios in `--silent` mode |
| `verify-signals.sh` | Verification script that queries the Datadog Security Signals Search API to confirm expected signals were generated, and submits a `security.regression.signal_found` custom metric per scenario for monitor alerting |
| `cronjob.yaml` | Two CronJobs: `detection-regression-runner` (runs scenarios every 6h at `:00`) and `detection-regression-verifier` (verifies signals 30 min later at `:30`) |
| `create-monitors.sh` | Creates 3 Datadog monitors via the API: per-scenario metric regression alert, RCE correlation signal absence alert, and CronJob failure alert |
| `setup.sh` | One-time setup: creates secrets, patches the app deployment to `runAsUser: 0`, creates ConfigMap, applies RBAC and CronJobs, creates the correlation rule, and creates monitors |

---

## Phase 1: One-Time Setup (Prerequisites)

### Step 1 — Namespace and Secrets

Create the required namespaces and the Datadog API key secret used by the Agent:

```bash
kubectl create namespace playground
kubectl create namespace datadog

kubectl create secret generic datadog-api-secret \
  --namespace datadog \
  --from-literal api-key="$DD_API_KEY"
```

### Step 2 — Deploy the Datadog Agent via Helm

Uses the existing Helm values at `deploy/datadog-agent.yaml` which enables:
- Runtime Security (CWS) with `securityAgent.runtime.enabled: true`
- APM + single-step instrumentation
- CWS instrumentation via admission controller (`mode: remote_copy`)
- SBOM scanning
- ASM threats detection
- Hash resolver for the fake malware binaries

```bash
helm repo add datadog https://helm.datadoghq.com
helm repo update
helm install datadog-agent datadog/datadog \
  --namespace datadog \
  -f deploy/datadog-agent.yaml
```

### Step 3 — Deploy the Playground App

Uses the existing manifest at `deploy/app.yaml`:
- Image: `docker.io/datadog/datadog-security-playground:latest`
- `imagePullPolicy: Always` ensures fresh pulls on each restart
- Label `admission.datadoghq.com/cws-instrumentation.enabled: "true"` enables CWS injection

```bash
kubectl apply -f deploy/app.yaml --namespace playground
```

### Step 4 — Run the Automated Setup

The `setup.sh` script handles all remaining one-time configuration:

```bash
export DD_API_KEY="<your-datadog-api-key>"
export DD_APP_KEY="<your-datadog-application-key>"
export DD_SITE="datadoghq.com"
./deploy/regression/setup.sh
```

This script performs the following:

1. **Creates secrets** — `datadog-regression-keys` in the `playground` namespace
   (stores `DD_API_KEY` and `DD_APP_KEY` for the verifier CronJob).

2. **Patches the playground-app deployment** — Sets `securityContext.runAsUser: 0`
   on the container so that the `findings-generator` scenario (which checks
   `$EUID == 0`) can run.

3. **Creates ConfigMap** — `scenario-runner-scripts` containing `run-scenarios.sh`
   and `verify-signals.sh`, mounted into the CronJob pods.

4. **Applies RBAC** — `scenario-runner` ServiceAccount, Role (get/list/patch
   deployments, get/list pods, create pods/exec), and RoleBinding.

5. **Applies CronJobs** — `detection-regression-runner` (schedule `0 */6 * * *`)
   and `detection-regression-verifier` (schedule `30 */6 * * *`).

6. **Creates the correlation detection rule** — Calls
   `assets/correlation/create-rule.sh` to create the
   `[Execution context] File download and execution activity` rule in Datadog.
   This rule groups 5 query stages (package_installation, file_download,
   new_binary_execution, cryptominer_execution, credential_access_imds) with a
   15-minute evaluation window.

7. **Creates Datadog monitors** — Calls `create-monitors.sh` to create:
   - **Per-scenario metric monitor**: Alerts when
     `security.regression.signal_found{scenario:*}` drops below 1 (12h window).
   - **RCE correlation signal monitor**: Event-v2 alert checking for the absence
     of the correlation signal (12h window).
   - **CronJob failure monitor**: Event-v2 alert on Kubernetes BackOff events
     for the runner job.

---

## Phase 2: Periodic Execution (Automated via CronJobs)

### Step 5 — Scenario Runner CronJob (`detection-regression-runner`)

Runs every 6 hours at `:00`. The `run-scenarios.sh` script performs:

1. **Restart deployment** — `kubectl rollout restart deployment/playground-app`
   triggers a new pod with `imagePullPolicy: Always`, pulling the latest image.

2. **Wait for CWS instrumentation** — 60-second delay (configurable via
   `WAIT_AFTER_RESTART`) for the admission controller to inject CWS
   instrumentation into the new pod.

3. **Resolve running pod** — Finds the Running pod by label `app=playground-app`
   and waits for the `Ready` condition.

4. **Execute scenarios** — Runs each scenario via `kubectl exec`:

   | # | Scenario | Command | Expected Detections |
   |---|----------|---------|---------------------|
   | 1 | RCE Malware | `/scenarios/rce-malware/detonate.sh --silent` | Correlation rule: package install → download → binary exec → cryptominer → IMDS access. Severities: CRITICAL (all 5), HIGH (4), MEDIUM (3), LOW (2). |
   | 2 | BPFDoor | `/scenarios/bpfdoor/detonate.sh --silent` | Backdoor execution, persistence via `/etc/rc.common`, process masquerading as `haldrund`. |
   | 3 | Findings Generator | `/scenarios/findings-generator/detonate.sh` | PCI DSS 11.5 findings: `pci_11_5_critical_binaries_chmod`, `_chown`, `_link`, `_rename`, `_open`, `_unlink`, `_utimes`. |
   | 4 | CoreDump Escape | `/scenarios/coredump-escape-container/detonate.sh` | `/proc/sys/kernel/core_pattern` write attempt (CVE-2022-0492 simulation). |

   Each scenario is followed by a 60-second wait (configurable via
   `WAIT_BETWEEN_SCENARIOS`) for detection processing.

### Step 6 — Signal Verifier CronJob (`detection-regression-verifier`)

Runs every 6 hours at `:30` (30 minutes after the runner to allow signal
propagation). The `verify-signals.sh` script performs:

1. **Query the Datadog Security Signals Search API** — For each scenario, sends a
   `POST /api/v2/security_monitoring/signals/search` request with a 90-minute
   lookback window (configurable via `--lookback`).

   Queries used:
   - **RCE Malware**: `rule.name:"[Execution context] File download and execution activity"`
   - **BPFDoor**: `type:workload_security service:playground-app`
   - **Findings Generator**: `type:workload_security @agent.rule_id:pci_11_5*`
   - **CoreDump Escape**: `type:workload_security service:playground-app core_pattern`

   > **Note**: These queries may need adjustment based on how signals appear in
   > your specific Datadog environment. Run the scenarios once manually and check
   > the Security Signals Explorer to verify exact rule names and attributes.

2. **Submit custom metrics** — For each scenario, sends a gauge metric
   `security.regression.signal_found` (value `1` for pass, `0` for fail) to
   `POST /api/v1/series` with tags `scenario:<name>`, `cluster:<cluster>`,
   `env:playground-env`.

3. **Report results** — Logs pass/fail per scenario. Exits with code 1 if any
   verification failed.

### Step 7 — Datadog Agent Updates

Agent upgrades are handled separately from scenario execution (to keep the
CronJob simple and focused). Run manually or from CI:

```bash
helm repo update
helm upgrade datadog-agent datadog/datadog \
  --namespace datadog \
  -f deploy/datadog-agent.yaml
```

---

## Phase 3: Monitoring & Alerting

### Step 8 — Datadog Monitors

Three monitors are created by `create-monitors.sh`:

#### Monitor 1: Per-Scenario Metric Regression Alert

```
Type:    query alert
Query:   min(last_12h):min:security.regression.signal_found{env:playground-env} by {scenario} < 1
```

Alerts when the custom metric submitted by `verify-signals.sh` indicates that
any scenario's expected signal was not found. Uses `notify_no_data: true` with a
24-hour no-data timeframe to also alert if the verifier stops running entirely.

#### Monitor 2: RCE Correlation Signal Absence

```
Type:    event-v2 alert
Query:   events("source:security_signals rule_name:\"[Execution context] File download and
         execution activity\" cluster_name:playground-cluster").rollup("count").last("12h") < 1
```

Direct backup check for the most critical signal (the RCE correlation chain).
Alerts if the signal is absent for 12 hours.

> **Note**: The event-v2 query syntax may need adjustment based on how security
> signals are indexed in your Datadog environment. Verify the correct source and
> attribute names in the Signals Explorer.

#### Monitor 3: CronJob Failure Alert

```
Type:    event-v2 alert
Query:   events("source:kubernetes reason:BackOff namespace:playground
         job_name:detection-regression-runner*").rollup("count").last("12h") > 0
```

Alerts when the scenario runner CronJob itself fails (e.g., pod crash, timeout,
RBAC issues).

### Step 9 — Optional Dashboard

Create a Datadog dashboard with:
- Timeline widget: `security.regression.signal_found` by `scenario` over time
- Monitor status widgets for each regression monitor
- Log stream of CronJob execution logs (if container log collection is enabled)
- Pod restart history for the `playground-app` deployment

---

## RBAC

The `rbac.yaml` manifest creates:

```yaml
ServiceAccount: scenario-runner          (namespace: playground)
Role: scenario-runner                    (namespace: playground)
  - apps/deployments:    get, list, patch
  - core/pods:           get, list
  - core/pods/exec:      create
RoleBinding: scenario-runner             (namespace: playground)
```

This is the minimum set of permissions for the CronJob to:
- Trigger a rollout restart (`patch` on deployments)
- Find the running pod (`get`, `list` on pods)
- Execute scenario scripts inside the pod (`create` on pods/exec)

---

## CronJob Configuration

### detection-regression-runner

| Setting | Value | Notes |
|---------|-------|-------|
| Schedule | `0 */6 * * *` | Every 6 hours at :00 |
| Image | `bitnami/kubectl:latest` | Debian-based, includes bash and curl |
| Concurrency | `Forbid` | Prevents overlapping runs |
| Deadline | 3600s (1 hour) | Timeout for the entire job |
| Backoff | 0 | No retries on failure |
| History | 5 successful, 5 failed | Retained for debugging |

### detection-regression-verifier

| Setting | Value | Notes |
|---------|-------|-------|
| Schedule | `30 */6 * * *` | 30 min after runner for signal propagation |
| Image | `bitnami/kubectl:latest` | Debian-based, includes bash and curl |
| Concurrency | `Forbid` | Prevents overlapping runs |
| Deadline | 600s (10 min) | Verification is fast |
| Backoff | 0 | No retries on failure |
| Secrets | `datadog-regression-keys` | DD_API_KEY and DD_APP_KEY |

---

## Environment Variables Reference

### run-scenarios.sh

| Variable | Default | Description |
|----------|---------|-------------|
| `PLAYGROUND_NAMESPACE` | `playground` | Kubernetes namespace |
| `APP_DEPLOYMENT` | `playground-app` | Deployment name |
| `WAIT_AFTER_RESTART` | `60` | Seconds to wait after restart for CWS init |
| `WAIT_BETWEEN_SCENARIOS` | `60` | Seconds between scenario runs |

### verify-signals.sh

| Variable | Default | Description |
|----------|---------|-------------|
| `DD_API_KEY` | *(required)* | Datadog API key |
| `DD_APP_KEY` | *(required)* | Datadog Application key |
| `DD_SITE` | `datadoghq.com` | Datadog site |
| `LOOKBACK_MINUTES` | `90` | How far back to search for signals |
| `SUBMIT_METRICS` | `true` | Submit custom metrics to Datadog |
| `CLUSTER_NAME` | `playground-cluster` | Cluster name for metric tags |

### setup.sh

| Variable | Default | Description |
|----------|---------|-------------|
| `DD_API_KEY` | *(required)* | Datadog API key |
| `DD_APP_KEY` | *(required)* | Datadog Application key |
| `DD_SITE` | `datadoghq.com` | Datadog site |
| `PLAYGROUND_NAMESPACE` | `playground` | Playground namespace |
| `DATADOG_NAMESPACE` | `datadog` | Agent namespace |
| `SKIP_MONITORS` | `false` | Skip monitor creation |
| `SKIP_CORRELATION_RULE` | `false` | Skip correlation rule creation |

---

## Operations

### Trigger a manual test run

```bash
kubectl create job --from=cronjob/detection-regression-runner manual-test-$(date +%s) -n playground
```

### Trigger manual signal verification

```bash
kubectl create job --from=cronjob/detection-regression-verifier manual-verify-$(date +%s) -n playground
```

### Check CronJob status

```bash
kubectl get cronjobs -n playground -l app=detection-regression
```

### View job logs

```bash
kubectl logs -n playground -l app=detection-regression --tail=100
```

### Run verification locally

```bash
export DD_API_KEY="..." DD_APP_KEY="..."
./deploy/regression/verify-signals.sh --lookback 120 --no-metrics
```

### Upgrade the Datadog Agent

```bash
helm repo update
helm upgrade datadog-agent datadog/datadog -n datadog -f deploy/datadog-agent.yaml
```

---

## Key Considerations

1. **Schedule frequency**: Every 6 hours is the default. The correlation rule uses
   a 15-minute evaluation window, so space scenario runs at least 15 minutes
   apart. The 60-second `WAIT_BETWEEN_SCENARIOS` is sufficient since scenarios
   run sequentially within a single pod.

2. **Pod cleanup**: The RCE malware scenario has a built-in cleanup step (kills
   the malware process, removes files, cleans persistence entries). BPFDoor does
   not have cleanup, but the pod restart between CronJob runs provides a clean
   state since each `rollout restart` creates a fresh container.

3. **Root requirement**: The `findings-generator` scenario requires `$EUID == 0`.
   The `setup.sh` script patches the playground-app deployment to run as
   `runAsUser: 0`. Without this patch, the findings-generator will exit
   immediately with an error.

4. **Image registry**: The app deployment in `deploy/app.yaml` points to
   `docker.io/datadog/datadog-security-playground:latest`. The CI pipeline
   publishes to `ghcr.io/datadog/datadog-security-playground`. Ensure the
   deployment manifest points to whichever registry receives the latest builds.

5. **Signal propagation latency**: Security signals can take 2-10 minutes to
   appear in Datadog after the triggering event. The 30-minute offset between
   the runner and verifier CronJobs accounts for this. If verification fails
   intermittently, increase `LOOKBACK_MINUTES`.

6. **Monitor tuning**: After the first few automated runs, check the Datadog
   Security Signals Explorer to verify that the queries in `verify-signals.sh`
   match the actual signal attributes in your environment. Adjust rule names,
   tag filters, and lookback windows as needed.

7. **Idempotency**: Each pod restart gives a fresh container, ensuring scenarios
   start from a clean state. The `setup.sh` script uses `--dry-run=client | kubectl apply`
   for secrets and ConfigMaps, making it safe to re-run.

---

## Source Files

### deploy/regression/rbac.yaml

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: scenario-runner
  namespace: playground
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: scenario-runner
  namespace: playground
rules:
  - apiGroups: ["apps"]
    resources: ["deployments"]
    verbs: ["get", "list", "patch"]
  - apiGroups: [""]
    resources: ["pods"]
    verbs: ["get", "list"]
  - apiGroups: [""]
    resources: ["pods/exec"]
    verbs: ["create"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: scenario-runner
  namespace: playground
subjects:
  - kind: ServiceAccount
    name: scenario-runner
    namespace: playground
roleRef:
  kind: Role
  name: scenario-runner
  apiGroup: rbac.authorization.k8s.io
```

### deploy/regression/run-scenarios.sh

```bash
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
```

### deploy/regression/verify-signals.sh

```bash
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
```

### deploy/regression/cronjob.yaml

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: detection-regression-runner
  namespace: playground
  labels:
    app: detection-regression
spec:
  # Run every 6 hours. Adjust to match your desired test cadence.
  # The schedule must allow enough time for signal propagation between runs.
  schedule: "0 */6 * * *"
  concurrencyPolicy: Forbid
  successfulJobsHistoryLimit: 5
  failedJobsHistoryLimit: 5
  jobTemplate:
    metadata:
      labels:
        app: detection-regression
    spec:
      backoffLimit: 0
      activeDeadlineSeconds: 3600
      template:
        metadata:
          labels:
            app: detection-regression
        spec:
          serviceAccountName: scenario-runner
          containers:
            - name: runner
              image: bitnami/kubectl:latest
              command: ["bash", "/scripts/run-scenarios.sh"]
              env:
                - name: PLAYGROUND_NAMESPACE
                  value: "playground"
                - name: APP_DEPLOYMENT
                  value: "playground-app"
                - name: WAIT_AFTER_RESTART
                  value: "60"
                - name: WAIT_BETWEEN_SCENARIOS
                  value: "60"
              volumeMounts:
                - name: scripts
                  mountPath: /scripts
                  readOnly: true
          volumes:
            - name: scripts
              configMap:
                name: scenario-runner-scripts
                defaultMode: 0755
          restartPolicy: Never
---
# Optional: separate CronJob that verifies signals after scenarios have run.
# This job runs 30 minutes after the scenario runner to allow signal propagation.
# Requires DD_API_KEY and DD_APP_KEY secrets.
apiVersion: batch/v1
kind: CronJob
metadata:
  name: detection-regression-verifier
  namespace: playground
  labels:
    app: detection-regression
spec:
  # Runs 30 minutes after the scenario runner (offset from 0 */6)
  schedule: "30 */6 * * *"
  concurrencyPolicy: Forbid
  successfulJobsHistoryLimit: 5
  failedJobsHistoryLimit: 5
  jobTemplate:
    metadata:
      labels:
        app: detection-regression
    spec:
      backoffLimit: 0
      activeDeadlineSeconds: 600
      template:
        metadata:
          labels:
            app: detection-regression
        spec:
          serviceAccountName: scenario-runner
          containers:
            - name: verifier
              image: bitnami/kubectl:latest
              command: ["bash", "/scripts/verify-signals.sh", "--lookback", "90"]
              env:
                - name: DD_API_KEY
                  valueFrom:
                    secretKeyRef:
                      name: datadog-regression-keys
                      key: api-key
                - name: DD_APP_KEY
                  valueFrom:
                    secretKeyRef:
                      name: datadog-regression-keys
                      key: app-key
                - name: DD_SITE
                  value: "datadoghq.com"
                - name: SUBMIT_METRICS
                  value: "true"
                - name: CLUSTER_NAME
                  value: "playground-cluster"
              volumeMounts:
                - name: scripts
                  mountPath: /scripts
                  readOnly: true
          volumes:
            - name: scripts
              configMap:
                name: scenario-runner-scripts
                defaultMode: 0755
          restartPolicy: Never
```

### deploy/regression/create-monitors.sh

```bash
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
    "query": "events(\"source:security_signals rule_name:\"[Execution context] File download and execution activity\" cluster_name:playground-cluster\").rollup(\"count\").last(\"12h\") < 1",
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
```

### deploy/regression/setup.sh

```bash
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
```
