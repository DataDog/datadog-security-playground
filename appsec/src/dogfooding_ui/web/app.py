from __future__ import annotations

from pathlib import Path
from typing import Any, Literal, TypedDict

from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import HTMLResponse, RedirectResponse
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates

from dogfooding_ui.core import registry
from dogfooding_ui.web.catalog import (
    CatalogPayload,
    build_catalog,
    build_catalog_payload,
)

Outcome = Literal["success", "failure"]

BASE_DIR = Path(__file__).resolve().parent
STATIC_DIR = BASE_DIR / "static"
TEMPLATES_DIR = BASE_DIR / "templates"

app = FastAPI(
    title="AppSec Dogfooding",
    description="Scenario catalog and execution console.",
)
app.mount(
    "/dogfooding/static",
    StaticFiles(directory=STATIC_DIR),
    name="dogfooding-static",
)

templates = Jinja2Templates(directory=str(TEMPLATES_DIR))


class ScenarioStepRunPayload(TypedDict):
    step_id: str
    step_display_name: str
    step_description: str
    duration_ms: int
    outcome: Outcome
    summary: str
    meta: object | None


class ScenarioRunPayload(TypedDict):
    scenario_name: str
    outcome: Outcome
    datadog_link: str | None
    step_results: list[ScenarioStepRunPayload]


def _overall_outcome(step_outcomes: tuple[str, ...]) -> Outcome:
    if not step_outcomes:
        return "success"
    if any(outcome == "failure" for outcome in step_outcomes):
        return "failure"
    return "success"


@app.get("/", include_in_schema=False)
def root() -> RedirectResponse:
    return RedirectResponse(url="/dogfooding")


@app.get("/dogfooding", response_class=HTMLResponse, include_in_schema=False)
def dogfooding_catalog_page(request: Request) -> HTMLResponse:
    template_context: dict[str, Any] = {
        "request": request,
        "groups": build_catalog(),
    }
    return templates.TemplateResponse(
        request,
        "dogfooding/index.html",
        template_context,
    )


@app.get("/dogfooding/api/catalog")
def dogfooding_catalog_api() -> CatalogPayload:
    return build_catalog_payload()


@app.post("/dogfooding/api/scenarios/{scenario_name}/run")
def dogfooding_scenario_run_api(scenario_name: str) -> ScenarioRunPayload:
    registry.load_scenarios()
    try:
        scenario_class = registry.by_name(scenario_name)
    except ValueError as error:
        raise HTTPException(status_code=404, detail=str(error)) from error

    try:
        run_result = scenario_class().execute()
    except Exception as error:
        raise HTTPException(
            status_code=500,
            detail=f"Failed to run scenario '{scenario_name}': {error}",
        ) from error

    step_results: list[ScenarioStepRunPayload] = [
        {
            "step_id": step_result.step_id,
            "step_display_name": step_result.step_display_name,
            "step_description": step_result.step_description,
            "duration_ms": step_result.duration_ms,
            "outcome": step_result.outcome,
            "summary": step_result.summary,
            "meta": step_result.meta,
        }
        for step_result in run_result.step_results
    ]
    outcomes = tuple(step_result.outcome for step_result in run_result.step_results)
    return {
        "scenario_name": run_result.scenario_name,
        "outcome": _overall_outcome(outcomes),
        "datadog_link": run_result.datadog_link,
        "step_results": step_results,
    }
