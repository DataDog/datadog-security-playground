# 🚨 FAKE BPFDoor - EDUCATIONAL PROJECT ONLY 🚨

## ⚠️ IMPORTANT DISCLAIMER ⚠️

**THIS PROJECT IS ENTIRELY FAKE AND HARMLESS**

- ✅ **EDUCATIONAL ONLY**: This code is designed for educational and demonstration purposes
- ✅ **NO MALICIOUS FUNCTIONALITY**: It contains no real or functional backdoor capabilities
- ✅ **SIMULATION**: This is a simulation that mimics BPF backdoor behavior without any harmful capabilities
- ✅ **SECURITY RESEARCH**: Intended for learning network security and intrusion detection concepts

**DO NOT USE FOR MALICIOUS PURPOSES**

---

## Project Description

This project is a **fake** and **educational** implementation of a "BPFDoor" - a simulation of a network backdoor using BPF (Berkeley Packet Filter) filters. The program demonstrates the following concepts:

### Simulated Features

1. **Process Camouflage**: Masquerades as a legitimate system process (`haldrund`)
2. **Daemonization**: Detaches from terminal and runs in background
3. **BPF Filtering**: Uses a complex BPF filter to analyze network packets
4. **Magic Signature**: Searches for a specific signature in packets (960051513)
5. **Raw Socket**: Uses raw sockets to capture network traffic

### Code Structure

- **fake-bpfdoor.c**: Main source code
- **Makefile**: Compilation script
- **fake-bpfdoor.x86**: Compiled binary

## Compilation

```bash
make
```

or directly:

```bash
gcc -o fake-bpfdoor.x86 fake-bpfdoor.c
```

## Usage

⚠️ **Warning**: Requires root privileges to create raw sockets

### Run the fake program

```bash
sudo ./fake-bpfdoor.x86
```

### Clean up (remove fake PID file)

```bash
sudo ./fake-bpfdoor.x86 clean
```

## Technical Analysis

### Simulation Process

1. **Instance Check**: Verifies if a "fake" instance is already running via `/var/run/haldrund.pid`
2. **Camouflage**: Uses `prctl(PR_SET_NAME)` to change the process name
3. **Classic Daemonization**:
   - Fork the parent process
   - Create a new session (`setsid`)
   - Change directory to `/`
   - Redirect file descriptors to `/dev/null`
4. **Socket Creation**: Raw TCP socket (`IPPROTO_TCP`)
5. **BPF Filter**: Apply a complex filter (251 instructions)
6. **Listening Loop**: Wait indefinitely for packets matching the filter

### BPF Filter

The BPF filter contains 251 instructions that analyze:
- IP headers (version, protocol)
- TCP/UDP headers
- Specific signatures in data
- Magic value `960051513` to trigger a response

## Educational Objectives

This project allows studying:

- **Network Security**: Understanding BPF filters
- **Intrusion Detection**: Recognizing backdoor patterns
- **System Programming**: Daemonization, raw sockets
- **Reverse Engineering**: Analysis of simulated malicious code

## Cleanup

To remove all generated files:

```bash
make clean
sudo rm -f /var/run/haldrund.pid
```

## Legal Warnings

- ⚠️ Use only in controlled test environments
- ⚠️ Do not deploy on production systems
- ⚠️ Respect all local cybersecurity laws
- ⚠️ Strictly educational and research use only

## Contributing

Contributions are welcome to improve the educational aspects of the project. Ensure that any modifications maintain the **fake** and **harmless** nature of the code.

---

**Reminder: This project is an EDUCATIONAL SIMULATION and does not constitute a functional malicious tool in any way.**
