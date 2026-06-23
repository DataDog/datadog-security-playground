# Deploying the Datadog Agent on Kubernetes

This guide explains how to deploy the Datadog Agent with the playground configuration on **any** Kubernetes cluster. It is environment-agnostic and can be reused for EKS, a local Lima VM, Minikube, or an existing cluster.

## 🛠️ Prerequisites

- A running **Kubernetes cluster** and a `kubectl` context pointing at it
- **kubectl**: [Installation Guide](https://kubernetes.io/docs/tasks/tools/)
- **Helm**: [Installation Guide](https://helm.sh/docs/intro/install/)

## 🌍 Configuration

Set these environment variables **once** before running the steps below. `DD_SITE` controls which Datadog data center your agent ships telemetry to; change it if you're not on US1. See the [Datadog site documentation](https://docs.datadoghq.com/getting_started/site/#access-the-datadog-site) for the full list of valid values.

```bash
export DD_SITE=datadoghq.com                  # your Datadog site
export DD_API_KEY=<your API key>              # https://app.datadoghq.com/organization-settings/api-keys
export DD_APP_KEY=<your application key>      # only needed for scenario 1 (rce-malware); requires security_monitoring_rules_write scope
```

## 🚀 Deployment

### Step 1: Create the Datadog API key secret

The playground's agent configuration (`deploy/datadog-agent.yaml`) references a secret named `datadog-api-secret`:

```bash
kubectl create secret generic datadog-api-secret --from-literal api-key="$DD_API_KEY"
```

### Step 2: Install the Datadog Agent with Helm

```bash
helm repo add datadog https://helm.datadoghq.com
helm repo update
helm install datadog-agent \
  --set datadog.site=$DD_SITE \
  -f deploy/datadog-agent.yaml \
  datadog/datadog
```

### Step 3: Verify the deployment

Wait until the agent pods are running before proceeding:

```bash
kubectl get pods
```

Expected output:

```
NAME                                           READY   STATUS    RESTARTS   AGE
datadog-agent-cluster-agent-7697f8cf97-mrsrg   1/1     Running   0          2m8s
datadog-agent-rzxs2                            4/4     Running   0          2m8s
```

## 🧹 Cleanup

To remove the Datadog Agent from your cluster:

```bash
helm uninstall datadog-agent
kubectl delete secret datadog-api-secret
```
