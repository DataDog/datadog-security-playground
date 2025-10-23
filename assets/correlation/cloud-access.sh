#!/bin/bash

# Parse command-line arguments for AWS credentials
if [ $# -eq 3 ]; then
    export AWS_ACCESS_KEY_ID="$1"
    export AWS_SECRET_ACCESS_KEY="$2"
    export AWS_SESSION_TOKEN="$3"
    echo "Using provided AWS credentials."
else
    echo "Invalid number of arguments. Please provide 3 arguments: AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, AWS_SESSION_TOKEN."
    exit 1
fi

INSTANCE_TYPE='m5.xlarge'
REGIONS=('us-east-1' 'us-west-2')
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
    # The --output json is standard for CLI parsing.
    LAUNCH_OUTPUT=$(aws ec2 run-instances \
        --image-id "$IMAGE_ID" \
        --instance-type "$INSTANCE_TYPE" \
        --min-count 1 \
        --max-count 1 \
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
