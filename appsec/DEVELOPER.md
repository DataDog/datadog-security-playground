# Developer Guide

This document explains how the AppSec dogfooding lab works and how to extend it safely.

## Project Layout

- `test_api/`
  - test API implementations used by scenarios
  - API contract is specified in `test_api/openapi.yaml`
- `src/`
  - `dogfooding_ui`
    - `core/`
      - `scenarios/`: definition of scenarios
      - `groups.py`: definition of scenario groups
      - ...: logic for defining and executing scenarios
    - `web`
      - `templates/` and `static/`: UI
      - `*.py`: FastAPI web app to run scenarios defined in python
  - `test_api_client`
    - Auto-generated API CLient for to access the test API
    - see [updating the test api client](#updating-the-test-api-and-client)

## Runtime Flow

### Catalog loading

- `GET /dogfooding` and `GET /dogfooding/api/catalog` call `build_catalog()`.
- Catalog uses each scenario's `steps()` to derive step metadata.
- `before()` / `after()` are not executed during catalog generation.

### Scenario execution

`POST /dogfooding/api/scenarios/{scenario_name}/run`:
1. Resolve scenario class from registry.
2. Instantiate and run `scenario.execute()`.
3. Return step results.

`Scenario.execute()` in `src/dogfooding_ui/core/model.py`:
1. Executes `before()`.
2. Executes all steps in order.
3. Executes `after()` in `finally`.

The test API base URL is configured through:
- `DOGFOODING_TEST_API_BASE_URL` (default `http://appsec-test-api:8000/`)

## Adding a New Scenario

1. Create a file under `src/dogfooding_ui/core/scenarios/` (for example `my_scenario.py`).
2. Define a subclass of `Scenario`.
3. Register it with `@register`.
4. Add it to a group in `src/dogfooding_ui/core/groups.py`.

Minimal structure:

```python
from dogfooding_ui.core.model import Scenario, Step, StepSummary
from dogfooding_ui.core.registry import register


@register
class MyScenario(Scenario):
    name = "my_scenario"
    display_name = "My Scenario"
    datadog_link_template = (
        "https://app.datadoghq.com/security/appsec/inventory/apis?query=service:{service_name}"
    )

    def before(self) -> None:
        pass

    def after(self) -> None:
        pass

    def steps(self) -> tuple[Step, ...]:
        return (self.my_step,)

    def my_step(self) -> StepSummary:
        return StepSummary(outcome="success", summary="Done.")
```

## Datadog Link Templating

- Scenario-level template field: `datadog_link_template`.
- Runtime variables available in `.format(...)`:
  - `{service_name}`: from `/health` response (`service_name`), URL-encoded


## Running the dogfooding ui locally During Development

Install [uv](https://docs.astral.sh/uv/getting-started/installation/)

- Run web app locally:

```bash
uv sync
uv run dev
```

- Run checks:

```bash
uv run pyright # Type checker
uv run ruff check # Linter
```

## Updating the Test API and Client

When changing API behavior or schema:

1. Update OpenAPI contract in `test_api/openapi.yaml`.
2. Update API implementations in `test_api/`.
3. Regenerate the client library:

```bash
./scripts/sync-api-client.py
```
