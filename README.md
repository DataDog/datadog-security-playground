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
- **Kubernetes cluster** (existing cluster or see infrastructure options below)
- **kubectl**: [Installation Guide](https://kubernetes.io/docs/tasks/tools/)
- **Helm Charts**: [Installation Guide](https://helm.sh/docs/intro/install/)

### Infrastructure Options

You can deploy this playground on:

1. **Your existing Kubernetes cluster** - Follow the deployment guide below
2. **Amazon EKS using Terraform** - See [Terraform EKS Setup](#-terraform-eks-setup-optional) section
3. **Local Minikube cluster** - For developers, see [DEVELOPER.md](DEVELOPER.md)

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

### Cleanup

To remove the playground from your cluster:

1. **Delete the Application:**
   ```bash
   kubectl delete -f deploy/app.yaml
   ```

2. **Uninstall the Datadog Agent:**
   ```bash
   helm uninstall datadog-agent
   ```

3. **Delete the API Key Secret:**
   ```bash
   kubectl delete secret $DATADOG_API_SECRET_NAME
   ```

## ☁️ Terraform EKS Setup (Optional)

If you don't have an existing Kubernetes cluster, you can use Terraform to create an Amazon EKS cluster with the playground application and Datadog Agent pre-configured.

### Prerequisites
- AWS credentials configured or passed as environment variables
- Terraform installed (>= 1.0)
- Datadog API key

### Deployment

Due to Terraform provider initialization requirements, deployment must be done in **two stages**:

#### Stage 1: Create the EKS Cluster and VPC

```bash
cd terraform/eks
terraform init
terraform apply -var="datadog_api_key=YOUR_API_KEY_HERE" \
    -target=module.vpc \
    -target=module.eks
```

This creates:
- VPC with public and private subnets
- EKS cluster with managed node groups
- Required IAM roles and policies

#### Stage 2: Deploy Kubernetes Resources

Once the cluster is created, deploy the Kubernetes resources:

```bash
terraform apply -var="datadog_api_key=YOUR_API_KEY_HERE"
```

This deploys:
- Kubernetes namespaces (`playground` and `datadog`)
- Service accounts and secrets
- Datadog Agent via Helm
- Playground application

### Access the Cluster

Update your kubeconfig to access the cluster:

```bash
aws eks --region $(terraform output -raw region) update-kubeconfig \
    --name $(terraform output -raw cluster_name)
```

For more details, see [terraform/eks/README.md](terraform/eks/README.md).

### Cleanup

To destroy the EKS cluster and all associated AWS resources:

```bash
cd terraform/eks
terraform destroy -var="datadog_api_key=YOUR_API_KEY_HERE"
```

This removes the EKS cluster, VPC, IAM roles, and all Kubernetes resources deployed by Terraform.

## 🎯 Available Attack Scenarios

Navigate to the `scenarios/` folder to explore available attack scenarios. Each scenario includes detailed documentation and step-by-step instructions.

### Current Scenarios

#### 1. Full chain RCE to malware download, persistence and cryptomining
- **Location**: `scenarios/rce-malware/`
- **Description**: Simulates a command injection attack that deploys a payload containing a cryptominer via file download, achieve persistence, and attempts to lateral move to the cloud. The aim is to showcase a complete compromise and generate a signal describing the full attack.
- **Attack Vector**: Command injection vulnerability
- **Impact**:
- **Detection**: Workload Protection signals for backdoor execution, network behavior, file modifications, and persistence mechanisms
- **Prerequisites**: Before running this scenario, you must first create the correlation detection rule in Datadog by running `assets/correlation/create-rule.sh` with the `DD_API_KEY`, `DD_APP_KEY`, and `DD_API_SITE` environment variables set. The `security_monitoring_rules_write` permission should be assigned to the `DD_APP_KEY`. The `DD_API_SITE` should be set to the Datadog site your are using, refer to the [Datadog documentation](https://docs.datadoghq.com/getting_started/site/#access-the-datadog-site) for available sites).

**How to Run:**
```bash
# Execute the attack simulation from within the playground-app pod
kubectl exec -it deploy/playground-app -- /scenarios/rce-malware/detonate.sh --wait
```

#### 2. BPFDoor Network Backdoor Attack
- **Location**: `scenarios/bpfdoor/`
- **Description**: Simulates a command injection attack that deploys a persistent BPFDoor network backdoor
- **Attack Vector**: Command injection vulnerability
- **Impact**: Covert network communication channels, process masquerading, persistence, system compromise
- **Detection**: Workload Protection signals for backdoor execution, network behavior, file modifications, and persistence mechanisms
- **Technical Features**: Process camouflage (haldrund), BPF packet filtering, raw socket communication, magic signature detection

**How to Run:**
```bash
# Execute the attack simulation from within the playground-app pod
kubectl exec -it deploy/playground-app -- /scenarios/bpfdoor/detonate.sh --wait
```

#### 3. Essential Linux Binary Modified - Findings Generator
- **Location**: `scenarios/findings-generator/`
- **Description**: Essential system binaries in containers are executable files that perform operating system functions and administrative tasks. These binaries typically reside in protected system directories such as `/bin`, `/sbin`, `/usr/bin`, and `/usr/sbin`. In containerized environments, these binaries are part of the container image layers and should be immutable during runtime. 
- **Attack Vector**: File system modifications to critical binaries
- **Impact**: Demonstrates detection of unauthorized changes to system binaries including download third party binaries, permission changes, ownership modifications, file renames, deletions, and timestamp tampering
- **Detection**: Workload Protection findings for Essential Linux binary modified on container (PCI DSS 11.5 compliance)
- **Operations**: chmod, chown, link, rename, open/modify, unlink, and utimes operations

**How to Run:**
```bash
# Execute all file operations (recommended)
kubectl exec -it deploy/playground-app -- /scenarios/findings-generator/detonate.sh

# Or run a specific operation
kubectl exec -it deploy/playground-app -- /scenarios/findings-generator/detonate.sh [chmod|chown|link|rename|open|unlink|utimes]
```

## 🎯 Atomic test organization

[Atomic Red Team](https://atomicredteam.io/) often contains multiple tests for the same ATT&CK technique. For example, the test identifier T1136.001-1 refers to the first test for MITRE ATT&CK technique T1136.001 (Create Account: Local Account). This test creates an account on a Linux system. The second test, T1136.001-2, creates an account on a MacOS system.

### Test against real-world threats

**Deploy Atomic Red Team Image:**
   ```bash
   kubectl apply -f deploy/redteam.yaml
   ```

**How to Run:**
```
kubectl exec -it <playground-app-pod-name> -- pwsh
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

## 🔧 Developer Resources

For local development, building binaries, and contributing to this project, see [DEVELOPER.md](DEVELOPER.md).
