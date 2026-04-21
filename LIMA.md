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

2. **Install the Datadog Agent with the playground configuration:**
   ```bash
   helm install datadog-agent -f deploy/datadog-agent.yaml datadog/datadog
   ```

3. **Wait until the agent pods are running before proceeding:**
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

## 🐳 Building and Loading Docker Image (Optional)

This step is optional and only needed if you want to deploy a locally built version of the playground application instead of the published image. If so, you need to build the Docker image and load it into the Lima VM before deploying the app.

### Step 1: Build the Docker Image

```bash
# add multiarch support
docker buildx create --use
```

```bash
# Build the Python application image
make build
```

### Step 2: Load Image into Lima

The Lima Kubernetes template uses `containerd` as the container runtime. Save the image from your local Docker daemon and import it into the VM's `k8s.io` containerd namespace:

```bash
docker save datadog/datadog-security-playground:latest | limactl shell k8s sudo ctr --namespace=k8s.io images import -
```
