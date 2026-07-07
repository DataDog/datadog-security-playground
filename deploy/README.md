# Deployment Manifests

This directory contains Kubernetes manifests and the Helm chart for the Datadog Security Playground.

## Helm Deployment (Recommended)

`helm/playground/` deploys both the playground app and the `langflow-vulnerable` container (real, pinned-by-digest [CVE-2025-3248](https://nvd.nist.gov/vuln/detail/CVE-2025-3248)):

```bash
helm install playground deploy/helm/playground --namespace playground --create-namespace

# Verify
kubectl get pods -n playground
```

Toggle either workload independently via `--set playgroundApp.enabled=false` / `--set langflowVulnerable.enabled=false`.

If you're provisioning the cluster with `terraform/eks/`, Terraform only creates the cluster and the `playground` namespace/service account — this Helm chart (and the Datadog Agent's own `helm install`, see the root [README.md](../README.md)) is applied afterwards, the same way regardless of how the cluster was created.

## Manual Deployment (legacy, playground app only)

```bash
kubectl apply -f deploy/app.yaml -n playground

# Verify
kubectl get pods -n playground
```
