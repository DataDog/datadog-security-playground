from http import HTTPStatus
from typing import ClassVar
from urllib.parse import quote

import httpx

from traffic_generator.core.model import (
    DATADOG_SITE,
    Scenario,
    Step,
    StepSummary,
    get_client,
)
from traffic_generator.core.registry import register

RASP_TRIGGER_ATTEMPTS = 20


class _RaspSinkScenario(Scenario):
    rasp_rule_id: ClassVar[str]
    rasp_attack_type: ClassVar[str]
    product_attack_label: ClassVar[str]
    request_route: ClassVar[str]
    request_payload_key: ClassVar[str]
    request_payload_value: ClassVar[str]

    def before(self) -> None:
        self.public_client: httpx.Client = get_client()

    def after(self) -> None:
        self.public_client.close()

    def steps(self) -> tuple[Step, ...]:
        return (self.trigger_rasp_signal,)

    def datadog_link(self, *, service_name: str | None) -> str | None:
        if service_name is None:
            return None

        query = quote(
            f"service:{service_name} @appsec.rule_id:{self.rasp_rule_id}",
            safe="",
        )
        return (
            f"https://app.{DATADOG_SITE}/security/appsec/investigate/traces"
            f"?query={query}"
        )

    def trigger_request(self) -> httpx.Response:
        return self.public_client.get(
            self.request_route,
            params={self.request_payload_key: self.request_payload_value},
        )

    def trigger_rasp_signal(self) -> StepSummary:
        """Generate runtime exploit attempts for App and API Protection detection."""
        http_errors = 0
        server_errors = 0

        for _ in range(RASP_TRIGGER_ATTEMPTS):
            try:
                response = self.trigger_request()
            except httpx.HTTPError:
                http_errors += 1
                continue

            if response.status_code >= HTTPStatus.INTERNAL_SERVER_ERROR:
                server_errors += 1

        if http_errors or server_errors:
            return StepSummary(
                outcome="failure",
                summary=(
                    f"RASP probe had {http_errors} HTTP errors and {server_errors} "
                    f"5xx responses over {RASP_TRIGGER_ATTEMPTS} attempts."
                ),
            )

        return StepSummary(
            outcome="success",
            summary=(
                f"Generated {RASP_TRIGGER_ATTEMPTS} runtime attack attempts on "
                f"`{self.request_route}`. Datadog App and API Protection can detect "
                f"attack attempts for the {self.product_attack_label} class."
            ),
        )


@register
class RaspSsrfScenario(_RaspSinkScenario):
    """Exploit SSRF vulnerability in URL fetch flows."""

    name = "rasp_ssrf"
    display_name = "RASP Detection: SSRF (/rasp/ssrf)"
    rasp_rule_id = "rasp-934-100"
    rasp_attack_type = "ssrf"
    product_attack_label = "server-side request forgery"
    request_route = "/rasp/ssrf"
    request_payload_key = "url"
    request_payload_value = "http://169.254.169.254/latest/meta-data/"


@register
class RaspShiScenario(_RaspSinkScenario):
    """Exploit command injection vulnerability in shell execution flows."""

    name = "rasp_shi"
    display_name = "RASP Detection: SHI (/rasp/shi)"
    rasp_rule_id = "rasp-932-100"
    rasp_attack_type = "command_injection"
    product_attack_label = "command injection"
    request_route = "/rasp/shi"
    request_payload_key = "command"
    request_payload_value = "dogfooding; id"


@register
class RaspLfiScenario(_RaspSinkScenario):
    """Exploit local file inclusion vulnerability in file access flows."""

    name = "rasp_lfi"
    display_name = "RASP Detection: LFI (/rasp/lfi)"
    rasp_rule_id = "rasp-930-100"
    rasp_attack_type = "lfi"
    product_attack_label = "local file inclusion"
    request_route = "/rasp/lfi"
    request_payload_key = "path"
    request_payload_value = "/etc/passwd"
