# Terraform for EKS

The Terraform code inside this repository provisions an EKS cluster, sized and configured for the security playground. It **only provisions cluster-level infrastructure** — the Datadog Agent and the playground/vulnerable-app workloads are deployed afterwards via Helm (see [Deploying Workloads](#deploying-workloads) below and the root [README.md](../../README.md)).

## Prerequisites

- AWS credentials configured or passed as environment variables
- Terraform installed (>= 1.0)

## Deployment

Due to Terraform provider initialization requirements, deployment must be done in **two stages**:

### Stage 1: Create the EKS Cluster and VPC

```bash
terraform init
terraform apply \
    -target=module.vpc \
    -target=module.eks
```

This creates:
- VPC with public and private subnets
- EKS cluster with managed node groups
- Required IAM roles and policies

### Stage 2: Create Kubernetes-side Cluster Resources

Once the cluster is created, apply the remaining resources:

```bash
terraform apply
```

This deploys:
- The `playground` namespace
- A service account (with IAM Pod Identity association) and its token secret
- An Ubuntu test pod for experimentation

## Access the Cluster

Update your kubeconfig to access the cluster:

```bash
aws eks --region $(terraform output -raw region) update-kubeconfig \
    --name $(terraform output -raw cluster_name)
```

## Deploying Workloads

Terraform stops at cluster + namespace/service-account provisioning. With the cluster reachable via `kubectl`, deploy the Datadog Agent and the playground workloads exactly as you would on any other cluster — see the [Deployment Guide](../../README.md#-deployment-guide) in the root README:

```bash
# 1. Datadog Agent (unchanged manual step)
helm install datadog-agent --set datadog.apiKeyExistingSecret=$DATADOG_API_SECRET_NAME \
    --set datadog.site=$DD_SITE -f ../../deploy/datadog-agent.yaml datadog/datadog

# 2. Playground app + langflow-vulnerable container
helm install playground ../../deploy/helm/playground --namespace playground
```

## What Gets Deployed

### Namespaces
- **`playground`**: Created by Terraform; holds the vulnerable security playground application and the `langflow-vulnerable` container once the Helm chart in step 2 above is installed.

### Resources
- EKS cluster with 2 managed node groups
- Pod Identity associations for AWS IAM integration
- Ubuntu test pod for experimentation

## File Structure

- `main.tf`: EKS cluster, VPC, and provider configurations
- `k8s.tf`: Kubernetes-side cluster resources (namespace, service account, test pod)
- `variables.tf`: Input variables
- `outputs.tf`: Output values
- `terraform.tf`: Terraform and provider version constraints

## Troubleshooting

**AWS token expires**: Get fresh credentials.

**Provider initialization errors**: Make sure to follow the two-stage deployment process. The Kubernetes provider needs the cluster to exist before it can initialize.