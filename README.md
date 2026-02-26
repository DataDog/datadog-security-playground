# Datadog Security Playground

A security simulation environment for demonstrating web application attacks and Datadog's detection capabilities. Run real-world attack scenarios in a controlled setting with harmless demo binaries.

## Disclaimer

**This is an educational simulation environment.**

- All scenarios use harmless demo binaries and simulated payloads
- No real malware or actual damage is caused
- Use only in isolated, controlled environments

## Prerequisites

- **Kubernetes cluster** (existing cluster or see infrastructure options below)
- **kubectl**: [Installation Guide](https://kubernetes.io/docs/tasks/tools/)
- **Helm**: [Installation Guide](https://helm.sh/docs/intro/install/)

### Infrastructure Options

1. **Existing Kubernetes cluster** — Follow the deployment guide below
2. **Amazon EKS via Terraform** — See [Terraform EKS Setup](#%EF%B8%8F-terraform-eks-setup-optional)
3. **Local Lima VM** — See [LIMA.md](LIMA.md)
4. **Local Minikube** — See [DEVELOPER.md](DEVELOPER.md)

## Deployment Guide

### Step 1: Deploy the Datadog Agent

1. **Create the API key secret:**
   ```bash
   export DATADOG_API_SECRET_NAME=datadog-api-secret
   kubectl create secret generic $DATADOG_API_SECRET_NAME --from-literal api-key="<YOUR_DATADOG_API_KEY>"
   ```

2. **Install the Datadog Agent:**
   ```bash
   helm repo add datadog https://helm.datadoghq.com
   helm repo update
   helm install datadog-agent \
     --set datadog.apiKeyExistingSecret=$DATADOG_API_SECRET_NAME \
     --set datadog.site=datadoghq.com \
     -f deploy/datadog-agent.yaml \
     datadog/datadog
   ```

3. **Verify the deployment:**
   ```bash
   kubectl get pods
   ```

   Expected output:
   ```
   NAME                                           READY   STATUS    RESTARTS   AGE
   datadog-agent-cluster-agent-7697f8cf97-mrsrg   1/1     Running   0          2m8s
   datadog-agent-rzxs2                            4/4     Running   0          2m8s
   ```

### Step 2: Deploy the Vulnerable Application

1. **Deploy:**
   ```bash
   kubectl apply -f deploy/app.yaml
   ```

2. **Verify:**
   ```bash
   kubectl get pods
   ```

   Expected output:
   ```
   NAME                                           READY   STATUS    RESTARTS   AGE
   datadog-agent-cluster-agent-7697f8cf97-mrsrg   1/1     Running   0          4m18s
   datadog-agent-rzxs2                            4/4     Running   0          4m18s
   playground-app-deployment-87b8d4b88-2hmzx      1/1     Running   0          1m30s
   ```

### Cleanup

Remove the playground from your cluster:

```bash
kubectl delete -f deploy/app.yaml
helm uninstall datadog-agent
kubectl delete secret $DATADOG_API_SECRET_NAME
```

## Terraform EKS Setup (Optional)

Create an Amazon EKS cluster with the playground and Datadog Agent pre-configured.

### Prerequisites
- AWS credentials configured or passed as environment variables
- Terraform >= 1.0
- Datadog API key

### Deployment

Due to Terraform provider initialization requirements, deployment requires two stages.

#### Stage 1: Create the EKS Cluster and VPC

```bash
cd terraform/eks
terraform init
terraform apply -var="datadog_api_key=YOUR_API_KEY_HERE" \
    -target=module.vpc \
    -target=module.eks
```

This creates a VPC with public and private subnets, an EKS cluster with managed node groups, and the required IAM roles.

#### Stage 2: Deploy Kubernetes Resources

```bash
terraform apply -var="datadog_api_key=YOUR_API_KEY_HERE"
```

This deploys namespaces (`playground` and `datadog`), service accounts, secrets, the Datadog Agent via Helm, and the playground application.

### Access the Cluster

```bash
aws eks --region $(terraform output -raw region) update-kubeconfig \
    --name $(terraform output -raw cluster_name)
```

See [terraform/eks/README.md](terraform/eks/README.md) for details.

### Cleanup

```bash
cd terraform/eks
terraform destroy -var="datadog_api_key=YOUR_API_KEY_HERE"
```

This removes the EKS cluster, VPC, IAM roles, and all Kubernetes resources deployed by Terraform.

## Attack Scenarios

Explore the `scenarios/` folder for available attack scenarios with step-by-step instructions.

### 1. Full-Chain RCE to Cryptomining

- **Location**: `scenarios/rce-malware/`
- **Description**: Simulates command injection that downloads a cryptominer payload, establishes persistence, and attempts lateral movement to the cloud — generating a signal describing the full attack chain.
- **Attack Vector**: Command injection
- **Detection**: Workload Protection signals for backdoor execution, network behavior, file modifications, and persistence mechanisms
- **Prerequisites**: Create the correlation detection rule by running `assets/correlation/create-rule.sh` with `DD_API_KEY`, `DD_APP_KEY`, and `DD_API_SITE` set. The `DD_APP_KEY` needs the `security_monitoring_rules_write` permission. See the [Datadog documentation](https://docs.datadoghq.com/getting_started/site/#access-the-datadog-site) for available `DD_API_SITE` values.

```bash
kubectl exec -it deploy/playground-app -- /scenarios/rce-malware/detonate.sh --wait
```

### 2. BPFDoor Network Backdoor

- **Location**: `scenarios/bpfdoor/`
- **Description**: Simulates command injection that deploys a persistent BPFDoor network backdoor with process camouflage, BPF packet filtering, raw socket communication, and magic signature detection.
- **Attack Vector**: Command injection
- **Impact**: Covert network channels, process masquerading, persistence, system compromise
- **Detection**: Workload Protection signals for backdoor execution, network behavior, file modifications, and persistence mechanisms

```bash
kubectl exec -it deploy/playground-app -- /scenarios/bpfdoor/detonate.sh --wait
```

### 3. Essential Linux Binary Modifications

- **Location**: `scenarios/findings-generator/`
- **Description**: Modifies essential system binaries in `/bin`, `/sbin`, `/usr/bin`, and `/usr/sbin` — which should be immutable in containers at runtime — to trigger Workload Protection findings (PCI DSS 11.5 compliance). Covers downloading third-party binaries, permission changes, ownership modifications, renames, deletions, and timestamp tampering.
- **Operations**: chmod, chown, link, rename, open/modify, unlink, utimes

```bash
# Run all operations (recommended)
kubectl exec -it deploy/playground-app -- /scenarios/findings-generator/detonate.sh

# Run a specific operation
kubectl exec -it deploy/playground-app -- /scenarios/findings-generator/detonate.sh [chmod|chown|link|rename|open|unlink|utimes]
```

## Atomic Red Team Tests

[Atomic Red Team](https://atomicredteam.io/) provides multiple tests per ATT&CK technique. For example, T1136.001-1 creates a local account on Linux, while T1136.001-2 does the same on macOS.

### Setup

```bash
kubectl apply -f deploy/redteam.yaml
```

### Running Tests

```
kubectl exec -it <playground-app-pod-name> -- pwsh
Invoke-AtomicTest T1105-27 -ShowDetails
Invoke-AtomicTest T1105-27 -GetPrereqs
Invoke-AtomicTest T1105-27
```

### Recommended Starting Points

These atomics emulate techniques observed in real attacks targeting cloud workloads.

| Atomic ID | Atomic Name | Datadog Rule | Source |
|-----------|-------------|--------------|--------|
| T1105-27 | [Linux Download File and Run](https://atomicredteam.io/command-and-control/T1105/#atomic-test-27---linux-download-file-and-run) | [Executable bit added to new file](https://docs.datadoghq.com/security/default_rules/executable_bit_added/) | [Source](https://blog.talosintelligence.com/teamtnt-targeting-aws-alibaba-2/) |
| T1046-2 | [Port Scan Nmap](https://atomicredteam.io/discovery/T1046/#atomic-test-2---port-scan-nmap) | [Network scanning utility executed](https://docs.datadoghq.com/security/default_rules/common_net_intrusion_util/) | [Source](https://blog.talosintelligence.com/teamtnt-targeting-aws-alibaba-2/) |
| T1574.006-1 | [Shared Library Injection via /etc/ld.so.preload](https://atomicredteam.io/defense-evasion/T1574.006/#atomic-test-1---shared-library-injection-via-etcldsopreload) | [Suspected dynamic linker hijacking attempt](https://docs.datadoghq.com/security/default_rules/suspected_dynamic_linker_hijacking/) | [Source](https://unit42.paloaltonetworks.com/hildegard-malware-teamtnt/) |
| T1053.003-2 | [Cron - Add script to all cron subfolders](https://atomicredteam.io/privilege-escalation/T1053.003/#atomic-test-2---cron---add-script-to-all-cron-subfolders) | [Cron job modified](https://docs.datadoghq.com/security/default_rules/cron_at_job_injection/) | [Source](https://blog.talosintelligence.com/rocke-champion-of-monero-miners/) |
| T1070.003-1 | [Clear Bash history (rm)](https://atomicredteam.io/defense-evasion/T1070.003/#atomic-test-1---clear-bash-history-(rm)) | [Shell command history modified](https://docs.datadoghq.com/security/default_rules/shell_history_tamper/) | [Source](https://unit42.paloaltonetworks.com/hildegard-malware-teamtnt/) |

For a full list of runtime detections, see the [OOTB rules](https://docs.datadoghq.com/security/default_rules/?category=cat-csm-threats) page. Every rule includes MITRE ATT&CK tactic and technique information.

### Techniques Not Relevant to Production Workloads

The MITRE ATT&CK [Linux Matrix](https://attack.mitre.org/matrices/enterprise/linux/) includes techniques for various purposes. The techniques in [notrelevant.md](notrelevant.md) target Linux workstations or are unlikely to be detected via OS events, so testing them is not recommended.

[Visualize with ATT&CK Navigator](https://mitre-attack.github.io/attack-navigator//#layerURL=https%3A%2F%2Fraw%2Egithubusercontent%2Ecom%2FDataDog%2Fworkload-security-evaluator%2Fmain%2Fnotrelevant_layer%2Ejson)

## Monitoring and Detection

After running any scenario:

1. Open the **Workload Protection App** in your Datadog dashboard
2. Review the **Security Signals** generated by the simulation
3. Analyze the **Attack Timeline** to understand the progression
4. Examine the **Detection Rules** that fired

## Developer Resources

For local development, building binaries, and contributing, see [DEVELOPER.md](DEVELOPER.md).
