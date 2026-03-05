# Onboarding Dogfooding

The goal of this sub-project is to test how easy it is to enable *App and API Protection* on an APM instrumented application and [how exhaustive our public documentation](https://docs.datadoghq.com/security/application_security/setup/) is.

The documentation is intentionally scarce as the public documentation should remain the single source of truth.

## Quick Start

```bash
# Clone repo
git clone git@github.com:DataDog/datadog-security-playground.git
cd datadog-security-playground/appsec/onboarding
```

This folder contains minimal Datadog APM-only stacks (no AppSec) built with Docker Compose.

1. Install required tools:
    - Docker: [installation instructions](https://docs.docker.com/get-started/get-docker/)
    - uv: [installation instructions](https://docs.astral.sh/uv/getting-started/installation/)

2. Set the Datadog API Key [Get one here](https://app.datadoghq.com/organization-settings/api-keys):
    - `export DD_API_KEY=<paste-api-key-here>`

3. Choose a configuration:
    - Plain apps:
      - Python (FastAPI): [docker-compose.apm-only.python-fastapi.yml](./onboarding/docker-compose.apm-only.python-fastapi.yml) | [instructions](#api-only-pythonfastapi)
      - Go (Gin): [docker-compose.apm-only.go-gin.yml](./onboarding/docker-compose.apm-only.go-gin.yml) | [instructions](#api-only-gogin)
    - Proxies:
      - Nginx + go app: [docker-compose.apm-only.nginx-go-gin.yml](./onboarding/docker-compose.apm-only.nginx-go-gin.yml) | [instructions](#nginx--gogin)
      - Envoy + go app: [docker-compose.apm-only.envoy-go-gin.yml](./onboarding/docker-compose.apm-only.envoy-go-gin.yml) | [instructions](#envoy--gogin)
      - HAProxy + go app: [docker-compose.apm-only.haproxy-go-gin.yml](./onboarding/docker-compose.apm-only.haproxy-go-gin.yml) | [instructions](#haproxy--gogin)

4. Start the stack:
     ```bash
     docker compose -f <docker compose file> up --build
     ```

5. In another terminal, start the traffic generator:
     ```bash
     uv run start

     # Open http://localhost:8080/dogfooding
     ```


## For SSI + MacOS only:

SSI does not work in docker-desktop. The simplest way to test it is to use lima to spawn a Linux VM.

```bash
# Install lima
brew install lima

# Make a lima VM with docker
limactl create --name=default template:docker-rootful

# Run a shell in the VM
lima

# /Users is mounted in the VM so you have access to the repo
# Run agent installation / docker commands in the VM
cd /Users/<my_macos_username>/datadog-security-playground/appsec/onboarding

# Follow quick start docs
```
