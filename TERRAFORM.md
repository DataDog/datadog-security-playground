# Terraform EKS Setup

If you don't have an existing Kubernetes cluster, you can use Terraform to create an Amazon EKS cluster with the playground application and Datadog Agent pre-configured.

## Prerequisites
- AWS credentials configured or passed as environment variables
- Terraform installed (>= 1.0)
- Datadog API key

## Deployment

Due to Terraform provider initialization requirements, deployment must be done in **two stages**:

### Stage 1: Create the EKS Cluster and VPC

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

### Stage 2: Deploy Kubernetes Resources

Once the cluster is created, deploy the Kubernetes resources:

```bash
terraform apply -var="datadog_api_key=YOUR_API_KEY_HERE"
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

For more details, see [terraform/eks/README.md](terraform/eks/README.md).

## Cleanup

To destroy the EKS cluster and all associated AWS resources:

```bash
cd terraform/eks
terraform destroy -var="datadog_api_key=YOUR_API_KEY_HERE"
```

This removes the EKS cluster, VPC, IAM roles, and all Kubernetes resources deployed by Terraform.
