# Deployment Manifests

This directory contains Kubernetes manifests and the Helm chart for the Datadog Security Playground.

## Helm Deployment (Recommended)

`helm/playground/` deploys the playground app:

```bash
helm install playground deploy/helm/playground --namespace playground --create-namespace

# Verify
kubectl get pods -n playground
```

If you're provisioning the cluster with `terraform/eks/`, Terraform only creates the cluster and the `playground` namespace/service account — this Helm chart (and the Datadog Agent's own `helm install`, see the root [README.md](../README.md)) is applied afterwards, the same way regardless of how the cluster was created.

## Manual Deployment (legacy, playground app only)

```bash
kubectl apply -f deploy/app.yaml -n playground

# Verify
kubectl get pods -n playground
```
