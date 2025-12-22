# Developer Guide

This guide is for developers who want to run the Datadog Security Playground locally using Minikube.

## 🛠️ Prerequisites

### Required Tools
- **Helm Charts**: [Installation Guide](https://helm.sh/docs/intro/install/)
- **Minikube**: [Installation Guide](https://minikube.sigs.k8s.io/docs/start)

## Minikube Setup

**Important:** Use [minikube version 1.36](https://github.com/kubernetes/minikube/releases/tag/v1.36.0) or older. Newer versions come with a custom 6.6 kernel without BTF support, which is not compatible with datadog agent.

**Configure Kubernetes Version:**
```bash
# Set Kubernetes version to 1.33.1
minikube config set kubernetes-version v1.33.1
```

Using a VM-based Minikube driver is mandatory, as the Docker driver will not provide the Linux kernel needed by the Datadog Agent.

For details on which drivers are supported on Linux and macOS, please see the [Minikube drivers documentation](https://minikube.sigs.k8s.io/docs/drivers/).

### Linux Setup

**Option 1 - KVM2 Driver (Recommended):**
```bash
minikube start --driver=kvm2
```

**Option 2 - QEMU Driver:**
```bash
minikube start --driver=qemu
```

### macOS Setup

**VirtualBox Driver (Recommended):**

First, install VirtualBox:
```bash
# Install VirtualBox via Homebrew
brew install --cask virtualbox
```

Then start Minikube:
```bash
minikube start --driver=virtualbox
```

## 🐳 Building and Loading Docker Image

Before deploying the Python application, you need to build the Docker image and load it into Minikube:

### Step 1: Build the Docker Image
```bash
# Build the Python application image
make build
```

### Step 2: Load Image into Minikube
```bash
# Load the image into Minikube's Docker daemon
make load
```

## 🔨 Building Binaries

Here's how to rebuild the simulation binaries:

### Build All Assets
```bash
# Build all simulation binaries
cd assets && make
```

### Build Individual Components
```bash
# Build BPFDoor simulator
cd assets/ && make bpfdoor

# Build malware simulator
cd assets/ && make malware
```

