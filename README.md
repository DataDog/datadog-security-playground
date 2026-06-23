# Datadog Security Playground

A comprehensive educational security simulation environment designed to demonstrate web application attack methodologies and showcase Datadog's Security capabilities. This playground provides hands-on experience with real-world attack scenarios in a controlled, safe environment.

## ⚠️ Important Disclaimer

**This is an educational simulation environment!**

- All attack scenarios use **harmless demo binaries** and simulated payloads
- Designed purely for security awareness and educational purposes
- Use only in isolated, controlled environments
- No real malware or actual damage is caused

## 🛠️ Prerequisites

### Required Tools
- **Kubernetes cluster** (existing cluster or see infrastructure options below)
- **kubectl**: [Installation Guide](https://kubernetes.io/docs/tasks/tools/)
- **Helm Charts**: [Installation Guide](https://helm.sh/docs/intro/install/)

### Infrastructure Options

You can deploy this playground on:

1. **Your existing Kubernetes cluster** - If you already have a working environment, you can directly jump to the [Configuration](#-configuration) section.
2. **Amazon EKS using Terraform** - See [TERRAFORM.md](TERRAFORM.md)
3. **Local Lima Kubernetes VM** - See [LIMA.md](LIMA.md)
4. **Local Minikube cluster** - For developers, see [DEVELOPER.md](DEVELOPER.md)

## 🌍 Configuration

Set these environment variables **once** before running any setup steps — they're referenced throughout this guide and by the correlation rule script. `DD_SITE` controls which Datadog data center your agent ships telemetry to; change it if you're not on US1. See [Datadog site documentation](https://docs.datadoghq.com/getting_started/site/#access-the-datadog-site) for the full list of valid values.

```bash
export DD_SITE=datadoghq.com                  # your Datadog site
export DD_API_KEY=<your API key>              # https://app.datadoghq.com/organization-settings/api-keys
export DD_APP_KEY=<your application key>      # only needed for scenario 1 (rce-malware); requires security_monitoring_rules_write scope
```

## 🚀 Deployment Guide

### Step 1: Deploy Datadog Agent

Follow [AGENT.md](AGENT.md) to deploy the Datadog Agent with the playground configuration on your Kubernetes cluster.

### Step 2: Deploy Vulnerable Application

1. **Deploy the Application:**
   ```bash
   kubectl apply -f deploy/app.yaml
   ```

2. **Wait for Application to be Ready:**
   ```bash
   kubectl get pods -n playground
   ```
   
   Expected output:
   ```
   NAME                                           READY   STATUS              RESTARTS   AGE
   playground-app-deployment-87b8d4b88-2hmzx      1/1     Running             0          1m30s
   ```

### Cleanup

To remove the playground from your cluster:

1. **Delete the Application:**
   ```bash
   kubectl delete -f deploy/app.yaml
   ```

2. **Uninstall the Datadog Agent and delete the API key secret** — see the [Cleanup](AGENT.md#-cleanup) section of AGENT.md.

## 🎯 Available Attack Scenarios

Navigate to the `scenarios/` folder to explore available attack scenarios. Each scenario includes detailed documentation and step-by-step instructions.

### Current Scenarios

#### 1. Full chain RCE to malware download, persistence and cryptomining
- **Location**: `scenarios/rce-malware/`
- **Description**: Simulates a command injection attack that deploys a payload containing a cryptominer via file download and achieve persistence. The aim is to showcase a complete compromise and generate a signal describing the full attack.
- **Attack Vector**: Command injection vulnerability
- **Impact**: Malware execution, establishing persistence, cryptocurrency mining
- **Detection**: Workload Protection signals for backdoor execution, network behavior, file modifications, and persistence mechanisms
- **Prerequisites**: Before running this scenario, you must first create the correlation detection rule in Datadog by running `assets/correlation/create-rule.sh` with `DD_API_KEY`, `DD_APP_KEY`, and `DD_SITE` exported (all three are covered by the [Configuration](#-configuration) section). The `DD_APP_KEY` must have the `security_monitoring_rules_write` scope.

**How to Run:**
```bash
# Execute the attack simulation from within the playground-app pod
kubectl exec -it -n playground deploy/playground-app -- /scenarios/rce-malware/detonate.sh --wait
```

#### 2. Cloud Access - AWS Credential Theft and Resource Abuse
- **Location**: `scenarios/cloud-access/`
- **Description**: Simulates cloud credential theft and resource abuse by retrieving AWS credentials from the Instance Metadata Service (IMDS) and attempting to launch expensive EC2 instances across multiple regions. This demonstrates how attackers pivot from workload compromise to cloud infrastructure abuse.
- **Attack Vector**: IMDS credential theft, unauthorized EC2 instance launches
- **Impact**: Cloud credential theft, unauthorized resource provisioning, financial abuse
- **Detection**: CloudTrail events for unauthorized EC2 RunInstances calls, IMDS access patterns

**How to Run:**
```bash
# Execute the attack simulation from within the playground-app pod
kubectl exec -it -n playground deploy/playground-app -- /scenarios/cloud-access/detonate.sh --wait
```

#### 3. BPFDoor Network Backdoor Attack
- **Location**: `scenarios/bpfdoor/`
- **Description**: Simulates a command injection attack that deploys a persistent BPFDoor network backdoor
- **Attack Vector**: Command injection vulnerability
- **Impact**: Covert network communication channels, process masquerading, persistence, system compromise
- **Detection**: Workload Protection signals for backdoor execution, network behavior, file modifications, and persistence mechanisms
- **Technical Features**: Process camouflage (haldrund), BPF packet filtering, raw socket communication, magic signature detection

**How to Run:**
```bash
# Execute the attack simulation from within the playground-app pod
kubectl exec -it -n playground deploy/playground-app -- /scenarios/bpfdoor/detonate.sh --wait
```

#### 4. Essential Linux Binary Modified - Findings Generator
- **Location**: `scenarios/findings-generator/`
- **Description**: Essential system binaries in containers are executable files that perform operating system functions and administrative tasks. These binaries typically reside in protected system directories such as `/bin`, `/sbin`, `/usr/bin`, and `/usr/sbin`. In containerized environments, these binaries are part of the container image layers and should be immutable during runtime. 
- **Attack Vector**: File system modifications to critical binaries
- **Impact**: Demonstrates detection of unauthorized changes to system binaries including download third party binaries, permission changes, ownership modifications, file renames, deletions, and timestamp tampering
- **Detection**: Workload Protection findings for Essential Linux binary modified in container (PCI DSS 11.5 compliance)
- **Operations**: chmod, chown, link, rename, open/modify, unlink, and utimes operations

**How to Run:**
```bash
# Execute all file operations (recommended)
kubectl exec -it -n playground deploy/playground-app -- /scenarios/findings-generator/detonate.sh

# Or run a specific operation
kubectl exec -it -n playground deploy/playground-app -- /scenarios/findings-generator/detonate.sh [chmod|chown|link|rename|open|unlink|utimes]
```

## 🎯 Atomic test organization

The playground can also run [Atomic Red Team](https://atomicredteam.io/) tests against real-world threats. See [ATOMIC.md](ATOMIC.md).

## 📊 Monitoring and Detection

### Datadog Workload Protection App

After running any attack scenario:

1. **Access Datadog Workload Protection App** in your Datadog dashboard
2. **Review Security Signals** generated by the attack simulation
3. **Analyze Attack Timeline** to understand the attack progression
4. **Examine Detection Rules** that triggered alerts

## 🔧 Developer Resources

For local development, building binaries, and contributing to this project, see [DEVELOPER.md](DEVELOPER.md).
