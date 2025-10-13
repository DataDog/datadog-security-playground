# Datadog Security Playground

A comprehensive educational security simulation environment designed to demonstrate web application attack methodologies and showcase Datadog's Workload Protection capabilities. This playground provides hands-on experience with real-world attack scenarios in a controlled, safe environment.

## ⚠️ Important Disclaimer

**This is an educational simulation environment!**

- All attack scenarios use **harmless demo binaries** and simulated payloads
- Designed purely for security awareness and educational purposes
- Use only in isolated, controlled environments
- No real malware or actual damage is caused

## 🛠️ Prerequisites

### Required Tools
- **Helm Charts**: [Installation Guide](https://helm.sh/docs/intro/install/)
- **Minikube** (optional): [Installation Guide](https://minikube.sigs.k8s.io/docs/start)

### Minikube Setup (optional)

Virtual machine-based Minikube is mandatory for this simulation.

**Important:** Use [minikube version 1.36](https://github.com/kubernetes/minikube/releases/tag/v1.36.0) or older. Newer versions come with a custom 6.6 kernel without BTF support, which is not compatible with datadog agent.

**Configure Kubernetes Version:**
```bash
# Set Kubernetes version to 1.33.1
minikube config set kubernetes-version v1.33.1
```

**Option 1 - QEMU Driver:**
```bash
minikube start --driver=qemu
```

**Option 2 - KVM2 Driver:**
```bash
minikube start --driver=kvm2
```

## 🐳 Building and Loading Docker Image

Before deploying the PHP application, you need to build the Docker image and load it into Minikube:

### Step 1: Build the Docker Image
```bash
# Build the PHP application image
make build
```

### Step 2: Load Image into Minikube
```bash
# Load the image into Minikube's Docker daemon
make load
```

## 🚀 Deployment Guide

### Step 1: Deploy Datadog Agent

1. **Set up API Secret:**
   ```bash
   export DATADOG_API_SECRET_NAME=datadog-api-secret
   ```

2. **Create Datadog API Key Secret:**
   ```bash
   kubectl create secret generic $DATADOG_API_SECRET_NAME --from-literal api-key="<YOUR_DATADOG_API_KEY>"
   ```

3. **Install Datadog Agent:**
   ```bash
   helm repo add datadog https://helm.datadoghq.com
   helm repo update
   helm install datadog-agent \
     --set datadog.apiKeyExistingSecret=$DATADOG_API_SECRET_NAME \
     --set datadog.site=datadoghq.com \
     -f deploy/datadog-agent.yaml \
     datadog/datadog
   ```

4. **Verify Datadog Agent Deployment:**
   ```bash
   kubectl get pods
   ```
   
   Expected output:
   ```
   NAME                                           READY   STATUS    RESTARTS   AGE
   datadog-agent-cluster-agent-7697f8cf97-mrsrg   1/1     Running   0          2m8s
   datadog-agent-rzxs2                            4/4     Running   0          2m8s
   ```

### Step 2: Deploy Vulnerable Application

1. **Deploy the Application:**
   ```bash
   kubectl apply -f deploy/app.yaml
   ```

2. **Wait for Application to be Ready:**
   ```bash
   kubectl get pods
   ```
   
   Expected output:
   ```
   NAME                                           READY   STATUS              RESTARTS   AGE
   datadog-agent-cluster-agent-7697f8cf97-mrsrg   1/1     Running             0          4m18s
   datadog-agent-rzxs2                            4/4     Running             0          4m18s
   playground-app-deployment-87b8d4b88-2hmzx             1/1     Running             0          1m30s
   ```

## 🎯 Available Attack Scenarios

Navigate to the `scenarios/` folder to explore available attack scenarios. Each scenario includes detailed documentation and step-by-step instructions.

### Current Scenarios

#### 1. Cryptocurrency Mining Malware Attack
- **Location**: `scenarios/malware/`
- **Description**: Simulates a command injection attack that deploys persistent cryptocurrency mining malware
- **Attack Vector**: Command injection vulnerability
- **Impact**: Resource hijacking, persistence, system compromise
- **Detection**: Workload Protection signals for malware execution, file modifications, and persistence mechanisms

**How to Run:**
```bash
# Execute the attack simulation from within the playground-app pod
kubectl exec -it deploy/playground-app -- /scenarios/malware/detonate.sh --wait
```

#### 2. BPFDoor Network Backdoor Attack
- **Location**: `scenarios/fake-bpfdoor/`
- **Description**: Simulates a command injection attack that deploys a persistent BPFDoor network backdoor
- **Attack Vector**: Command injection vulnerability
- **Impact**: Covert network communication channels, process masquerading, persistence, system compromise
- **Detection**: Workload Protection signals for backdoor execution, network behavior, file modifications, and persistence mechanisms
- **Technical Features**: Process camouflage (haldrund), BPF packet filtering, raw socket communication, magic signature detection

**How to Run:**
```bash
# Execute the attack simulation from within the playground-app pod
kubectl exec -it deploy/playground-app -- /scenarios/fake-bpfdoor/detonate.sh --wait
```

## 🎯 Atomic test organization

[Atomic Red Team](https://atomicredteam.io/) often contains multiple tests for the same ATT&CK technique. For example, the test identifier T1136.001-1 refers to the first test for MITRE ATT&CK technique T1136.001 (Create Account: Local Account). This test creates an account on a Linux system. The second test, T1136.001-2, creates an account on a MacOS system.

### Test against real-world threats

**How to Run:**
```
kubectl exec -it deploy/playground-app -- pwsh
Invoke-AtomicTest T1105-27 -ShowDetails
Invoke-AtomicTest T1105-27 -GetPrereqs # Download packages or payloads
Invoke-AtomicTest T1105-27
```

The following atomics are recommended as a starting point. They emulate techniques that were observed in real attacks targeting cloud workloads.

| Atomic ID | Atomic Name | Datadog Rule |Source|
|-----------|-------------|--------------|------|
|T1105-27|[Linux Download File and Run](https://atomicredteam.io/command-and-control/T1105/#atomic-test-27---linux-download-file-and-run)|[Executable bit added to new file](https://docs.datadoghq.com/security/default_rules/executable_bit_added/)|[Source](https://blog.talosintelligence.com/teamtnt-targeting-aws-alibaba-2/)|
|T1046-2|[Port Scan Nmap](https://atomicredteam.io/discovery/T1046/#atomic-test-2---port-scan-nmap)|[Network scanning utility executed](https://docs.datadoghq.com/security/default_rules/common_net_intrusion_util/)|[Source](https://blog.talosintelligence.com/teamtnt-targeting-aws-alibaba-2/)|
|T1574.006-1|[Shared Library Injection via /etc/ld.so.preload](https://atomicredteam.io/defense-evasion/T1574.006/#atomic-test-1---shared-library-injection-via-etcldsopreload)|[Suspected dynamic linker hijacking attempt](https://docs.datadoghq.com/security/default_rules/suspected_dynamic_linker_hijacking/)|[Source](https://unit42.paloaltonetworks.com/hildegard-malware-teamtnt/)|
|T1053.003-2|[Cron - Add script to all cron subfolders](https://atomicredteam.io/privilege-escalation/T1053.003/#atomic-test-2---cron---add-script-to-all-cron-subfolders)|[Cron job modified](https://docs.datadoghq.com/security/default_rules/cron_at_job_injection/)|[Source](https://blog.talosintelligence.com/rocke-champion-of-monero-miners/)
|T1070.003-1|[Clear Bash history (rm)](https://atomicredteam.io/defense-evasion/T1070.003/#atomic-test-1---clear-bash-history-(rm))|[Shell command history modified](https://docs.datadoghq.com/security/default_rules/shell_history_tamper/)|[Source](https://unit42.paloaltonetworks.com/hildegard-malware-teamtnt/)|

For a full list of Datadog's runtime detections, visit the [Out-of-the-box (OOTB) rules](https://docs.datadoghq.com/security/default_rules/?category=cat-csm-threats) page. MITRE ATT&CK tactic and technique information is provided for every rule.

### Techniques not relevant to production workloads

The MITRE ATT&CK [Linux Matrix](https://attack.mitre.org/matrices/enterprise/linux/) contains techniques for Linux hosts with a variety of purposes. Testing the techniques located in [notrelevant.md](notrelevant.md) is not recommended, because they are focused on Linux workstations or are unlikely to be detected using operating system events.

[Visualize with ATT&CK Navigator](https://mitre-attack.github.io/attack-navigator//#layerURL=https%3A%2F%2Fraw%2Egithubusercontent%2Ecom%2FDataDog%2Fworkload-security-evaluator%2Fmain%2Fnotrelevant_layer%2Ejson).

## 📊 Monitoring and Detection

### Datadog Workload Protection App

After running any attack scenario:

1. **Access Datadog Workload Protection App** in your Datadog dashboard
2. **Review Security Signals** generated by the attack simulation
3. **Analyze Attack Timeline** to understand the attack progression
4. **Examine Detection Rules** that triggered alerts

## 🔨 Optional: Building Binaries

Here's how to rebuild the simulation binaries:

### Build All Assets
```bash
# Build all simulation binaries
cd assets && make
```

### Build Individual Components
```bash
# Build BPFDoor simulator
cd assets/ && make fake-bpfdoor

# Build malware simulator
cd assets/ && make malware
```
