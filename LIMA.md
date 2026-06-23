# Lima / Colima VM Setup

This guide walks you through setting up the Datadog Security Playground locally using a VM-based Kubernetes cluster. Both **Lima** (via `limactl`) and **Colima** (a macOS-friendly wrapper around Lima) are supported. The key requirement is that Kubernetes runs directly inside a Linux VM — not inside Docker containers — so the Datadog Agent's CWS eBPF probes can attach to the VM's kernel.

## 🛠️ Prerequisites

### Required Tools
- **Lima** or **Colima**: [Lima installation](https://lima-vm.io/docs/installation/) · [Colima installation](https://github.com/abiosoft/colima#installation)
- **Helm Charts**: [Installation Guide](https://helm.sh/docs/intro/install/)

### Supported Environments
- macOS
- Linux

## 🚀 Setup

Choose **one** of the two approaches below depending on whether you have Lima or Colima installed.

---

### Option A: Lima

#### Step 1: Create a Kubernetes VM with Lima

```bash
limactl start --name k8s k8s-noble.yaml
```

> **Note:** This pins the VM to Ubuntu 24.04 (kernel 6.8). The default `template:k8s` currently uses Ubuntu 26.04 (kernel 7.x), which is incompatible with the Datadog agent's CWS eBPF probes.

#### Step 2: Configure kubectl

Set the `KUBECONFIG` environment variable so `kubectl` connects to the Lima Kubernetes cluster:

```bash
export KUBECONFIG=$(limactl list k8s --format 'unix://{{.Dir}}/copied-from-guest/kubeconfig.yaml')
```

#### Step 3: Deploy Datadog Agent

1. **Export your Datadog credentials** (change `DD_SITE` if you're not on US1 — see [Datadog site documentation](https://docs.datadoghq.com/getting_started/site/#access-the-datadog-site) for valid values):
   ```bash
   export DD_SITE=datadoghq.com
   export DD_API_KEY=<your API key>              # https://app.datadoghq.com/organization-settings/api-keys
   export DD_APP_KEY=<your application key>      # only needed for scenario 1 (rce-malware); requires security_monitoring_rules_write scope
   ```

2. **Add the Datadog Helm repository and create the API key secret:**
   ```bash
   helm repo add datadog https://helm.datadoghq.com
   helm repo update datadog
   kubectl create secret generic datadog-api-secret --from-literal api-key="$DD_API_KEY"
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

#### Step 4: Deploy the Playground Application

```bash
kubectl apply -f deploy/namespace.yaml
kubectl apply -f deploy/app.yaml
```

#### Step 5: Validate the Deployment

```bash
kubectl get pods -n playground -w
```

#### Step 6: Access the Playground

Set up port-forwarding to access the UI:

```bash
kubectl port-forward -n playground deployments/playground-app 5000:5000
```

The playground is now accessible at [http://localhost:5000](http://localhost:5000).

---

### Option B: Colima

[Colima](https://github.com/abiosoft/colima) is a popular macOS container runtime built on top of Lima. Its `--kubernetes` flag runs K3s directly inside the VM, giving the Datadog Agent the same direct kernel access as the Lima approach above.

> **Note:** Do **not** use `colima start` (without `--kubernetes`) and then run minikube with `--driver=docker` against Colima's Docker socket. That setup results in Kubernetes running inside Docker containers, which blocks CWS eBPF probes — CWS self-tests will fail and no Workload Protection signals will fire.

#### Step 1: Start a Colima VM with Kubernetes

```bash
colima start k8s --kubernetes --kubernetes-version v1.33.1+k3s1 --cpu 4 --memory 8
```

This creates a dedicated `k8s` Colima profile running K3s on Ubuntu 24.04 (kernel 6.8) and automatically updates your kubeconfig.

> **Tip:** Check available K3s releases at [github.com/k3s-io/k3s/releases](https://github.com/k3s-io/k3s/releases) — use the `v<version>+k3s1` tag format.

#### Step 2: Deploy Datadog Agent

1. **Export your Datadog credentials:**
   ```bash
   export DD_SITE=datadoghq.com
   export DD_API_KEY=<your API key>
   export DD_APP_KEY=<your application key>   # only needed for scenario 1 (rce-malware)
   ```

2. **Add the Datadog Helm repository and create the API key secret:**
   ```bash
   helm repo add datadog https://helm.datadoghq.com
   helm repo update datadog
   kubectl create secret generic datadog-api-secret --from-literal api-key="$DD_API_KEY"
   ```

3. **Install the Datadog Agent:**
   ```bash
   helm install datadog-agent \
     --set datadog.apiKeyExistingSecret=datadog-api-secret \
     --set datadog.site=$DD_SITE \
     -f deploy/datadog-agent.yaml \
     datadog/datadog
   ```

4. **Wait until the agent pods are running:**
   ```bash
   kubectl get pods -w -A
   ```

#### Step 3: Deploy the Playground Application

```bash
kubectl apply -f deploy/app.yaml
kubectl get pods -n playground -w
```

#### Step 4: Access the Playground

```bash
kubectl port-forward -n playground deployments/playground-app 5000:5000
```

The playground is now accessible at [http://localhost:5000](http://localhost:5000).

---

## 🐳 Building and Loading Docker Image (Optional)

This step is only needed if you want to deploy a locally built version of the playground application. Build the image first with `make build`, then load it into the VM.

### Lima

The Lima Kubernetes template uses `containerd`. Save the image from your local Docker daemon and import it into the VM's `k8s.io` containerd namespace:

```bash
docker save datadog/datadog-security-playground:latest | limactl shell k8s sudo ctr --namespace=k8s.io images import -
```

### Colima

Colima K3s uses Docker (via cri-dockerd) as the container runtime. Load the image directly into the `colima-k8s` Docker context — K3s will find it there:

```bash
docker --context colima save datadog/datadog-security-playground:latest | docker --context colima-k8s load
```
