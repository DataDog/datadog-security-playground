# Azure Kubernetes Service (AKS) Setup

This guide covers deploying the Datadog Security Playground on Azure Kubernetes Service using the Terraform module in `terraform/aks/`.

## Prerequisites

- [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli) installed and authenticated (`az login`)
- An active Azure subscription
- [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.3
- [kubectl](https://kubernetes.io/docs/tasks/tools/) and [Helm](https://helm.sh/docs/intro/install/) installed
- A Datadog API key

## Authenticate with Azure

```bash
az login
az account set --subscription "<your-subscription-id>"
```

## Deployment

Due to Terraform provider initialization requirements, deployment is done in two stages.

### Stage 1: Create the AKS Cluster and Networking

```bash
cd terraform/aks
terraform init
terraform apply -var="datadog_api_key=YOUR_API_KEY_HERE" \
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
- Virtual Network and subnet
- AKS cluster with system and user node pools (OIDC issuer + Workload Identity enabled)
- User-assigned managed identity with federated credential for the playground service account

### Stage 2: Deploy Kubernetes Resources

Once the cluster is ready, deploy the Kubernetes resources:

```bash
terraform apply -var="datadog_api_key=YOUR_API_KEY_HERE"
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
| `kubernetes_version` | `1.34` | Kubernetes version |
| `playground_namespace` | `playground` | App namespace |
| `datadog_namespace` | `datadog` | Datadog agent namespace |
| `datadog_api_key` | — | **Required** — your Datadog API key |
| `datadog_site` | `datadoghq.com` | Your Datadog site |

Override any variable on the command line:

```bash
terraform apply \
    -var="datadog_api_key=YOUR_KEY" \
    -var="location=eastus" \
    -var="vm_size=Standard_D4s_v3"
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

To destroy the AKS cluster and all associated Azure resources:

```bash
cd terraform/aks
terraform destroy -var="datadog_api_key=YOUR_API_KEY_HERE"
```

Or from the repo root:

```bash
make aks-destroy
```
