# Deployment Manifests

This directory contains Kubernetes manifests for the Datadog Security Playground.

## Terraform Deployment (Recommended)

All manifests can be automatically deployed via Terraform (alongside with the agent and everything that is needed). See `terraform/eks/` for the configuration.

## Manual Deployment

```bash
kubectl apply -f deploy/app.yaml -n playground

# Verify
kubectl get pods -n playground
```
