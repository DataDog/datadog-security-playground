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
limactl start --name k8s k8s-noble.yaml
```

> **Note:** This pins the VM to Ubuntu 24.04 (kernel 6.8). The default `template:k8s` currently uses Ubuntu 26.04 (kernel 7.x), which is incompatible with the Datadog agent's CWS eBPF probes.

### Step 2: Configure kubectl

Set the `KUBECONFIG` environment variable so `kubectl` connects to the Lima Kubernetes cluster:

```bash
export KUBECONFIG=$(limactl list k8s --format 'unix://{{.Dir}}/copied-from-guest/kubeconfig.yaml')
```

### Step 3: Deploy the Datadog Agent

Follow [AGENT.md](AGENT.md) to deploy the Datadog Agent on the Lima Kubernetes cluster. Make sure the `KUBECONFIG` you exported in Step 2 is still set so the agent is installed into the Lima VM.

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
