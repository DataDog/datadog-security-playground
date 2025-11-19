#!/bin/bash

set -e

DD_API_URL="${DD_API_URL:-api.datadoghq.com}"

# Check if required environment variables are set
if [ -z "$DD_API_KEY" ]; then
    echo "Error: DD_API_KEY environment variable is not set"
    exit 1
fi

if [ -z "$DD_APP_KEY" ]; then
    echo "Error: DD_APP_KEY environment variable is not set"
    exit 1
fi

if [ -z "$DD_API_URL" ]; then
    echo "Error: DD_API_URL environment variable is not set"
    exit 1
fi

# Get the directory where the script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RULE_FILE="$SCRIPT_DIR/backend-rule.json"

# Check if the rule file exists
if [ ! -f "$RULE_FILE" ]; then
    echo "Error: backend-rule.json not found at $RULE_FILE"
    exit 1
fi

echo "Creating detection rule from $RULE_FILE..."

# Make the API request
response=$(curl -X POST "https://$DD_API_URL/api/v2/security_monitoring/rules" \
    -H "DD-API-KEY: $DD_API_KEY" \
    -H "DD-APPLICATION-KEY: $DD_APP_KEY" \
    -H "Content-Type: application/json" \
    -d @"$RULE_FILE" \
    -w "\nHTTP_STATUS: %{http_code}" \
    -s)

# Extract HTTP status code
http_status=$(echo "$response" | grep "HTTP_STATUS" | cut -d: -f2)
response_body=$(echo "$response" | sed '/HTTP_STATUS/d')

# Check if the request was successful
if [ "$http_status" -eq 200 ] || [ "$http_status" -eq 201 ]; then
    echo "✓ Detection rule created successfully!"
    echo "Response:"
    echo "$response_body" | jq '.' 2>/dev/null || echo "$response_body"
else
    echo "✗ Failed to create detection rule (HTTP $http_status)"
    echo "Response:"
    echo "$response_body" | jq '.' 2>/dev/null || echo "$response_body"
    exit 1
fi
