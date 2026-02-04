# Deployment Manifests

This directory contains Kubernetes manifests for the Datadog Security Playground.

## Terraform Deployment (Recommended)

All manifests can also be automatically deployed via Terraform. See `terraform/eks/` for the configuration.

## Manual Deployment

### Prerequisites

Set your Datadog credentials as environment variables:

```bash
export DD_API_KEY="your-datadog-api-key"
export DD_SITE="datadoghq.com"  # or datadoghq.eu, us3.datadoghq.com, etc.
```

### Deploy Playground App

The `app.yaml` contains template variables (`${dd_api_key}`, `${dd_site}`) that need to be substituted:

```bash
# Deploy with variable substitution
sed -e "s/\${dd_api_key}/$DD_API_KEY/g" \
    -e "s/\${dd_site}/$DD_SITE/g" \
    deploy/app.yaml | kubectl apply -f -

# Verify
kubectl get pods -n playground
```

## Terraform Deployment (Recommended)

All manifests can also be automatically deployed via Terraform (alongside with the agent and everything that is needed). See `terraform/eks/` for the configuration.


