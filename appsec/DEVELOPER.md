# Developer Guide

## Quick Start

From `appsec/`:

```bash
uv sync
uv run dev
```

Open: `http://localhost:8080/dogfooding`

Checks before pushing:

```bash
uv run ruff check src
uv run pyright
```

## Where To Edit

- Scenario logic: `src/traffic_generator/core/scenarios/`
- Scenario grouping: `src/traffic_generator/core/groups.py`
- Scenario execution model: `src/traffic_generator/core/model.py`
- Scenario registry: `src/traffic_generator/core/registry.py`
- Catalog building (grouped + ungrouped): `src/traffic_generator/web/catalog.py`
- API routes: `src/traffic_generator/web/app.py`
- UI template: `src/traffic_generator/web/templates/dogfooding/index.html`
- UI behavior: `src/traffic_generator/web/static/dogfooding.js`
- UI styles: `src/traffic_generator/web/static/dogfooding.css`

## Add a Scenario

1. Create a class in `src/traffic_generator/core/scenarios/`.
2. Add `@register`.
3. Implement `before()`, `after()`, `steps()`.
4. Return `StepSummary(outcome="success"|"failure", summary="...")` from each step.
5. Decide grouping:
   - Add to a group in `groups.py` => appears under that section.
   - Do nothing => appears as ungrouped (top-level) scenario.

Minimal example:

```python
from traffic_generator.core.model import Scenario, Step, StepSummary
from traffic_generator.core.registry import register


@register
class MyScenario(Scenario):
    name = "my_scenario"
    display_name = "My Scenario"

    def before(self) -> None:
        pass

    def after(self) -> None:
        pass

    def steps(self) -> tuple[Step, ...]:
        return (self.my_step,)

    def my_step(self) -> StepSummary:
        return StepSummary(outcome="success", summary="Done.")
```
