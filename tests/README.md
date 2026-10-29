# Tests

These tests verify the Datadog Agent properly detects security events triggered by playground scenarios.

## Architecture

```
pytest process
├── gRPC test server (port 10000) ← receives security events from the agent
├── AppClient → sends commands to the playground /inject endpoint
└── test assertions (check rule IDs in received events)
```

## Prerequisites

- Python 3.12+
- Docker

## Dependencies

```bash
cd tests
python -m pip install -r requirements.txt
```

## Running tests locally

### 1. Build and start the playground app

```bash
# From the repository root
docker build -t playground-app -f app/Dockerfile .
docker run -d --name playground-app --net=host playground-app
```

### 2. Start the DD Agent with runtime security enabled

```bash
docker run -d \
  --name dd-agent \
  --cgroupns=host \
  --pid=host \
  --net=host \
  --security-opt=apparmor:unconfined \
  --cap-add=SYS_ADMIN \
  --cap-add=SYS_RESOURCE \
  --cap-add=SYS_PTRACE \
  --cap-add=NET_ADMIN \
  --cap-add=NET_BROADCAST \
  --cap-add=NET_RAW \
  --cap-add=IPC_LOCK \
  --cap-add=CHOWN \
  -v /var/run/docker.sock:/var/run/docker.sock:ro \
  -v /etc/os-release:/host/etc/os-release:ro \
  -v /etc/passwd:/etc/passwd:ro \
  -v /etc/group:/etc/group:ro \
  -v /sys/fs/cgroup/:/host/sys/fs/cgroup:ro \
  -v /proc/:/host/proc/:ro \
  -v /:/host/root:ro \
  -v /sys/kernel/debug:/sys/kernel/debug \
  -v $(pwd)/tests/agent_config/system-probe.yaml:/etc/datadog-agent/system-probe.yaml:ro \
  -e DD_RUNTIME_SECURITY_CONFIG_ENABLED=true \
  -e DD_API_KEY=dummy \
  -e HOST_PROC=/host/proc \
  -e HOST_ROOT=/host/root \
  datadog/agent:latest
```

### 3. Run the tests

```bash
cd tests
python -m pytest test_rce_malware.py -v -s
```

### 4. Cleanup

```bash
docker rm -f dd-agent playground-app
```

## Environment variables

| Variable | Default | Description |
|---|---|---|
| `TEST_SERVER_PORT` | `10000` | gRPC server port |
| `TEST_SERVER_VERBOSE` | `false` | Log every received event |
| `CONNECTION_TIMEOUT` | `120` | Seconds to wait for the agent to connect |
| `POST_CONNECTION_DELAY` | `5` | Seconds to wait after connection before running tests |
| `APP_URL` | `http://localhost:5000` | Playground app base URL |

## Regenerating gRPC stubs

If `runtime_security_server/proto/api.proto` is updated, regenerate the Python stubs:

```bash
cd tests
python -m runtime_security_server.generate_proto
```

This compiles `api.proto` and fixes the import paths in the generated files so they work as part of the `runtime_security_server` package.
