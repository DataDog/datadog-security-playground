from __future__ import annotations

import inspect
import os
import time
from abc import ABC, abstractmethod
from collections.abc import Callable
from dataclasses import dataclass
from http import HTTPStatus
from typing import Any, ClassVar, Literal
from urllib.parse import quote

from test_api_client.api.default import health
from test_api_client.models.health_response import HealthResponse

from test_api_client import AuthenticatedClient, Client

StepOutcome = Literal["success", "failure"]

TEST_API_BASE_URL = os.getenv(
    "DOGFOODING_TEST_API_BASE_URL",
    "http://localhost:8000/",
)
DATADOG_SITE = os.getenv("DD_SITE", "datadoghq.com")


def get_client() -> Client:
    return Client(base_url=TEST_API_BASE_URL)


def get_authed_client(token: str) -> AuthenticatedClient:
    return AuthenticatedClient(base_url=TEST_API_BASE_URL, token=token)


@dataclass(slots=True, frozen=True)
class StepSummary:
    outcome: StepOutcome
    summary: str
    meta: dict[str, Any] | None = None


type Step = Callable[[], StepSummary]
type Steps = Step


@dataclass(slots=True, frozen=True)
class StepMetadata:
    id: str
    display_name: str
    description: str


def step_metadata(
    step: Step,
) -> StepMetadata:
    step_id = getattr(step, "__name__", "")
    if not step_id:
        msg = "Step function must define a non-empty __name__."
        raise ValueError(msg)

    docstring = inspect.getdoc(step) or ""
    doc_lines = [line.strip() for line in docstring.splitlines()]

    if doc_lines and doc_lines[0]:
        display_name = doc_lines[0]
        description = "\n".join(line for line in doc_lines[1:] if line).strip()
    else:
        display_name = step_id.replace("_", " ").capitalize()
        description = ""

    return StepMetadata(
        id=step_id,
        display_name=display_name,
        description=description,
    )


@dataclass(slots=True, frozen=True)
class StepExecutionResult:
    step_id: str
    step_display_name: str
    step_description: str
    duration_ms: int
    outcome: StepOutcome
    summary: str
    meta: object | None = None


@dataclass(slots=True, frozen=True)
class ScenarioRunResult:
    scenario_name: str
    step_results: tuple[StepExecutionResult, ...]
    datadog_link: str | None = None

    @property
    def succeeded(self) -> bool:
        return all(step.outcome == "success" for step in self.step_results)

    @property
    def failed_step_ids(self) -> tuple[str, ...]:
        return tuple(
            step.step_id for step in self.step_results if step.outcome != "success"
        )


class Scenario(ABC):
    name: ClassVar[str]
    display_name: ClassVar[str | None] = None
    datadog_link_template: ClassVar[str | None] = os.getenv(
        "DOGFOODING_DATADOG_LINK_TEMPLATE"
    )

    @classmethod
    def scenario_name(cls) -> str:
        if cls.name:
            return cls.name
        msg = f"Scenario class '{cls.__name__}' must define a non-empty name."
        raise ValueError(msg)

    @classmethod
    def scenario_display_name(cls) -> str:
        if cls.display_name:
            return cls.display_name
        return cls.scenario_name()

    @classmethod
    def scenario_description(cls) -> str:
        return inspect.getdoc(cls) or ""

    @abstractmethod
    def before(self) -> None: ...

    @abstractmethod
    def after(self) -> None: ...

    @abstractmethod
    def steps(self) -> tuple[Step, ...]:
        """Return ordered step functions for this scenario."""

    def resolve_service_name(self) -> str | None:
        try:
            with get_client() as client:
                health_response = health.sync_detailed(client=client)
        except Exception:  # noqa: BLE001
            return None

        if health_response.status_code != HTTPStatus.OK:
            return None

        parsed = health_response.parsed
        if not isinstance(parsed, HealthResponse):
            return None

        service_name = parsed.service_name.strip()
        return service_name or None

    def datadog_link(self, *, service_name: str | None) -> str | None:
        template = self.datadog_link_template
        if template is None or service_name is None:
            return None

        try:
            return template.format(
                dd_site=DATADOG_SITE,
                service_name=quote(service_name, safe=""),
            )
        except IndexError, KeyError, ValueError:
            return None

    def execute(self) -> ScenarioRunResult:
        service_name = self.resolve_service_name()
        self.before()
        try:
            return self.execute_steps(
                steps=self.steps(),
                service_name=service_name,
            )
        finally:
            self.after()

    def execute_steps(
        self,
        *,
        steps: tuple[Step, ...],
        service_name: str | None = None,
    ) -> ScenarioRunResult:
        results: list[StepExecutionResult] = []
        for step in steps:
            metadata = step_metadata(step)
            started_at = time.perf_counter()
            summary = step()

            duration_ms = int((time.perf_counter() - started_at) * 1000)
            results.append(
                StepExecutionResult(
                    step_id=metadata.id,
                    step_display_name=metadata.display_name,
                    step_description=metadata.description,
                    duration_ms=duration_ms,
                    outcome=summary.outcome,
                    summary=summary.summary,
                    meta=summary.meta,
                ),
            )

        return ScenarioRunResult(
            scenario_name=self.scenario_name(),
            step_results=tuple(results),
            datadog_link=self.datadog_link(service_name=service_name),
        )

    def run(self) -> ScenarioRunResult:
        result = self.execute()
        if result.succeeded:
            return result

        failed_steps = ", ".join(result.failed_step_ids)
        msg = (
            f"Scenario '{self.scenario_name()}' failed. Failing steps: {failed_steps}."
        )
        raise RuntimeError(msg)


class ScenarioGroup:
    name: ClassVar[str]
    display_name: ClassVar[str | None] = None
    scenarios: ClassVar[tuple[type[Scenario], ...]] = ()

    @classmethod
    def group_name(cls) -> str:
        if cls.name:
            return cls.name
        msg = f"Scenario group class '{cls.__name__}' must define a non-empty name."
        raise ValueError(msg)

    @classmethod
    def group_display_name(cls) -> str:
        if cls.display_name:
            return cls.display_name
        return cls.group_name()

    @classmethod
    def group_description(cls) -> str:
        return inspect.getdoc(cls) or ""
