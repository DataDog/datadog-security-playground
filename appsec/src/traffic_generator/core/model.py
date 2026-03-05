import inspect
import os
import random
import time
from abc import ABC, abstractmethod
from collections.abc import Callable
from dataclasses import dataclass
from http import HTTPStatus
from typing import Any, ClassVar, Literal, cast
from urllib.parse import quote

import httpx

StepOutcome = Literal["success", "failure"]

TEST_API_BASE_URL = os.getenv(
    "DOGFOODING_TEST_API_BASE_URL",
    "http://localhost:8000/",
)
DATADOG_SITE = os.getenv("DD_SITE", "datadoghq.com")
TEST_API_TIMEOUT_SECONDS = float(os.getenv("DOGFOODING_TEST_API_TIMEOUT_SECONDS", "5"))


def _random_public_ipv4() -> str:
    random_source = random.SystemRandom()
    # Pick from a known global range to avoid retries over special-use blocks.
    return ".".join(
        (
            "11",
            str(random_source.randrange(0, 256)),
            str(random_source.randrange(0, 256)),
            str(random_source.randrange(1, 255)),
        )
    )


PUBLIC_TEST_SOURCE_IP = _random_public_ipv4()
APPSEC_ATTACKER_UNBLOCK_LINK = (
    f"https://app.{DATADOG_SITE}/security/appsec/investigate/attackers"
    f"?column=count&fromUser=false&group=ip&ipAttacker={PUBLIC_TEST_SOURCE_IP}"
    "&paused=true"
)
APPSEC_BLOCK_RESPONSE_MARKERS = (
    "you've been blocked",
    "security provided by datadog",
)


class AppSecBlockedError(RuntimeError):
    """Raised when Datadog AppSec blocks an HTTP request."""

    def __init__(self, *, request_route: str | None = None) -> None:
        """Store the blocked request route for scenario error reporting."""
        self.request_route = request_route
        super().__init__("Request blocked by Datadog AppSec")


def raise_if_block_response(response: httpx.Response) -> None:
    if is_block_response(response):
        raise AppSecBlockedError(request_route=response.request.url.path)


def get_client(*, headers: dict[str, str] | None = None) -> httpx.Client:
    request_headers = {"X-Forwarded-For": PUBLIC_TEST_SOURCE_IP}
    if headers is not None:
        request_headers.update(headers)

    return httpx.Client(
        base_url=TEST_API_BASE_URL,
        headers=request_headers,
        event_hooks={"response": [raise_if_block_response]},
        timeout=TEST_API_TIMEOUT_SECONDS,
    )


def get_authed_client(token: str) -> httpx.Client:
    return get_client(headers={"Authorization": f"Bearer {token}"})


@dataclass(slots=True, frozen=True)
class StepSummary:
    outcome: StepOutcome
    summary: str
    meta: dict[str, Any] | None = None


def blocked_by_appsec_step_summary() -> StepSummary:
    return StepSummary(
        outcome="failure",
        summary=("You've been blocked by App and API Protection."),
        meta={"unblock_link": APPSEC_ATTACKER_UNBLOCK_LINK},
    )


def is_block_response(response: httpx.Response) -> bool:
    if response.status_code != HTTPStatus.FORBIDDEN:
        return False

    content_type = response.headers.get("content-type", "").lower()
    if (
        content_type
        and "application/json" not in content_type
        and "text/html" not in content_type
    ):
        return False

    try:
        body = response.text.lower()
    except httpx.ResponseNotRead:
        try:
            response.read()
            body = response.text.lower()
        except httpx.HTTPError:
            return False

    return any(marker in body for marker in APPSEC_BLOCK_RESPONSE_MARKERS)


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
                health_response = client.get("/health")
        except AppSecBlockedError, httpx.HTTPError:
            return None

        if health_response.status_code != HTTPStatus.OK:
            return None

        try:
            payload = health_response.json()
        except ValueError:
            return None

        if not isinstance(payload, dict):
            return None

        payload_object = cast("dict[str, object]", payload)
        service_name = payload_object.get("service_name")
        if not isinstance(service_name, str):
            return None

        service_name = service_name.strip()
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
            blocked_error = False
            try:
                summary = step()
            except AppSecBlockedError:
                summary = blocked_by_appsec_step_summary()
                blocked_error = True

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
            if blocked_error:
                break

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
