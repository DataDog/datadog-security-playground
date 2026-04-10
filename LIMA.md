# Lima VM Setup

This guide walks you through setting up the Datadog Security Playground locally using a Lima Kubernetes VM.

## 🛠️ Prerequisites

### Required Tools
- **Lima**: [Installation Guide](https://lima-vm.io/docs/installation/)
- **Helm Charts**: [Installation Guide](https://helm.sh/docs/intro/install/)

### Supported Environments
- macOS
- Linux

## 🚀 Setup

### Step 1: Create a Kubernetes VM with Lima

```bash
limactl start template:k8s
```

### Step 2: Configure kubectl

Set the `KUBECONFIG` environment variable so `kubectl` connects to the Lima Kubernetes cluster:

```bash
export KUBECONFIG=$(limactl list k8s --format 'unix://{{.Dir}}/copied-from-guest/kubeconfig.yaml')
```

### Step 3: Deploy Datadog Agent

1. **Add the Datadog Helm repository and create the API key secret:**
   ```bash
   helm repo add datadog https://helm.datadoghq.com
   helm repo update
   kubectl create secret generic datadog-api-secret --from-literal api-key="<YOUR_DATADOG_API_KEY>"
   ```
   
2. **Set your Datadog site:**
   ```bash
   export DD_SITE=datadoghq.com  # replace with your site if not US1 - see https://docs.datadoghq.com/getting_started/site/
   ```

3. **Install the Datadog Agent with the playground configuration:**
   ```bash
   helm install datadog-agent \
     --set datadog.site=$DD_SITE \
     -f deploy/datadog-agent.yaml \
     datadog/datadog
   ```

4. **Wait until the agent pods are running before proceeding:**
   ```bash
   kubectl get pods -w -A
   ```

### Step 4: Deploy the Playground Application

```bash
kubectl apply -f deploy/namespace.yaml
kubectl apply -f deploy/app.yaml
```

### Step 5: Validate the Deployment

```bash
kubectl get pods -n playground -w
```

### Step 6: Access the Playground

Set up port-forwarding to access the UI:

```bash
kubectl port-forward -n playground deployments/playground-app 5000:5000
```

The playground is now accessible at [http://localhost:5000](http://localhost:5000).
