# Terraform for EKS

The Terraform code inside this repository provides a simple way to create an EKS cluster with Datadog monitoring and a security playground application.

## Prerequisites

- AWS credentials configured or passed as environment variables
- Terraform installed (>= 1.0)
- Datadog API key
- (Optional) Datadog site if yours differs from `datadoghq.com`.

## Deployment

Due to Terraform provider initialization requirements, deployment must be done in **two stages**:

### Stage 1: Create the EKS Cluster and VPC

```bash
terraform init
terraform apply -var="datadog_api_key=YOUR_API_KEY_HERE" \
    -var="datadog_site=datadoghq.com" \
    -target=module.vpc \
    -target=module.eks
```

**Note**: The `datadog_site` variable is optional and defaults to `datadoghq.com`. Common values include:
- `datadoghq.com`
- `datadoghq.eu`
- `us3.datadoghq.com`
- `us5.datadoghq.com`
- `ap1.datadoghq.com`
- `ddog-gov.com`

This creates:
- VPC with public and private subnets
- EKS cluster with managed node groups
- Required IAM roles and policies

### Stage 2: Deploy Kubernetes Resources

Once the cluster is created, deploy the Kubernetes resources:

```bash
terraform apply -var="datadog_api_key=YOUR_API_KEY_HERE" \
    -var="datadog_site=datadoghq.com"
```

This deploys:
- Kubernetes namespaces (`playground` and `datadog`)
- Service accounts and secrets
- Datadog Agent via Helm
- Playground application

## Access the Cluster

Update your kubeconfig to access the cluster:

```bash
aws eks --region $(terraform output -raw region) update-kubeconfig \
    --name $(terraform output -raw cluster_name)
```

## What Gets Deployed

### Namespaces
- **`playground`**: Contains the vulnerable security playground application
- **`datadog`**: Contains the Datadog Agent for monitoring and security

### Resources
- EKS cluster (v1.29) with 2 managed node groups
- Datadog Agent deployed via Helm chart
- Ubuntu test pod for experimentation
- Pod Identity associations for AWS IAM integration

## File Structure

- `main.tf`: EKS cluster, VPC, and provider configurations
- `k8s.tf`: Kubernetes resources (namespaces, deployments, etc.)
- `variables.tf`: Input variables
- `outputs.tf`: Output values
- `terraform.tf`: Terraform and provider version constraints

## Troubleshooting

**AWS token expires**: Get fresh credentials.

**Provider initialization errors**: Make sure to follow the two-stage deployment process. The Kubernetes provider needs the cluster to exist before it can initialize.