#!/bin/bash

# Define the IMDS endpoint IP
IMDS_IP="169.254.169.254"
IMDS_BASE_URL="http://${IMDS_IP}/latest/meta-data/iam/security-credentials/"

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

# Try to get credentials from IMDS first
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

INSTANCE_TYPE='m5.xlarge'
REGIONS=('us-east-1' 'us-west-2' 'us-east-2' 'us-west-1' 'eu-west-1' 'eu-central-1' 'ap-southeast-1' 'ap-northeast-1')
IMAGE_ID='ami-00000000000000000' # Likely not existing

echo "Attempting to launch EC2 instances with $INSTANCE_TYPE instance type..."
echo ""

# Check for AWS CLI
if ! command -v aws &> /dev/null
then
    echo "AWS CLI is not installed. Please install it to proceed."
    exit 1
fi

# Loop through the defined regions
for REGION in "${REGIONS[@]}"; do
    echo "Attempting to launch $INSTANCE_TYPE in $REGION..."

    # The command to launch the instance. We use 'run-instances'.
    # We deliberately use an invalid AMI_ID to force a failure (and a CloudTrail log entry).
    LAUNCH_OUTPUT=$(aws ec2 run-instances \
        --image-id "$IMAGE_ID" \
        --instance-type "$INSTANCE_TYPE" \
        --count 1 \
        --region "$REGION" 2>&1)

    # Check the exit status of the previous command
    if [ $? -eq 0 ]; then
        # If the command succeeds, parse the instance ID (less likely due to invalid AMI)
        INSTANCE_ID=$(echo "$LAUNCH_OUTPUT" | grep '"InstanceId":' | awk '{print $2}' | tr -d '",')
        echo "Successfully launched $INSTANCE_TYPE in $REGION. Instance ID: $INSTANCE_ID"
    else
        # If the command fails (which is the goal for logging attempts)
        # We look for the 'ClientError' line to extract the error code
        ERROR_CODE=$(echo "$LAUNCH_OUTPUT" | grep -oP '(?<=\<Code\>).*?(?=\</Code\>)' | head -1)

        if [ -n "$ERROR_CODE" ]; then
            echo "EC2 launch failed for $INSTANCE_TYPE in $REGION: $ERROR_CODE"
        else
            # A more generic failure occurred (e.g., region not available, CLI error)
            echo "Error launching $INSTANCE_TYPE in $REGION. Check output for details."
            # Uncomment the next line to see the full error output:
            # echo "$LAUNCH_OUTPUT"
        fi
    fi
done
