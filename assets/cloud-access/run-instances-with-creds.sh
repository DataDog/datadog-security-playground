#!/bin/bash

# ============================================================================
# Cloud Access demo - Step 2 of 2: cloud resource abuse with stolen credentials
# ============================================================================
#
# This step  uses the AWS credentials stolen in step 1 to attempt launching
# expensive EC2 instances across multiple regions, generating CloudTrail RunInstances events.
# An invalid AMI id is used so the launches fail and no real instances are ever created.

CREDS_FILE="${CLOUD_ACCESS_CREDS_FILE:-/tmp/.aws-cloud-access-creds}"

# Load the credentials staged by step 1.
if [ -f "$CREDS_FILE" ]; then
    . "$CREDS_FILE"
    export AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
    echo "Using provided AWS credentials to launch EC2 instances."
elif [ $# -eq 3 ]; then
    # Fallback: genuinely use the command-line arguments.
    export AWS_ACCESS_KEY_ID="$1"
    export AWS_SECRET_ACCESS_KEY="$2"
    export AWS_SESSION_TOKEN="$3"
    echo "Using provided AWS credentials from command-line arguments."
else
    echo "Error: no staged credentials file (${CREDS_FILE}) and no credentials provided." >&2
    echo "Run cloud-access-step1.sh first, or pass three arguments:" >&2
    echo "  $0 AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN" >&2
    exit 1
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
