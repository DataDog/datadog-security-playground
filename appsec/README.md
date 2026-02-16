# AppSec Dogfooding Lab

This lab showcases Datadog App and API Protection with:
- a test API instrumented with Datadog
- a web UI that runs traffic and attack scenarios against that API
- direct links from scenario results to Datadog product views

## Prerequisites

Required tools:
- Docker (with `docker compose`)

Required credentials:
- Datadog API key (`DD_API_KEY`)

## Quick Start

From this `appsec/` directory:

### 1. Set environment variables

```bash
export DD_API_KEY="<your_datadog_api_key>"
export DD_SITE="datadoghq.com"   # optional, defaults to datadoghq.com
export DD_ENV="local"            # optional
```

### 2. Choose a test API flavor

Choose an implementation of the test API in:
- python/fastapi
- ... (more to come)

```bash
TEST_API_FLAVOR="python/fastapi"
```

### 3. Start the full lab

```bash
docker compose --profile "$TEST_API_FLAVOR" up --build -d
```

This starts:
- the datadog agent
- the test API
- the test lab UI on `http://localhost:8080/dogfooding`

### 4. Open the UI

Navigate to:

`http://localhost:8080/dogfooding`

Then:
1. Expand a scenario.
2. Click `Run scenario`.
3. Review step-by-step execution results.
4. Use the Datadog result link card to inspect findings in Datadog.

## Stop the Lab

```bash
docker compose --profile "$TEST_API_FLAVOR" down
```

## Developer Documentation

See `DEVELOPER.md` for architecture details, scenario authoring, and API client regeneration workflow.
