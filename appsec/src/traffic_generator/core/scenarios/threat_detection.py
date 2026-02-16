from http import HTTPStatus
from typing import TYPE_CHECKING, ClassVar
from urllib.parse import quote

from traffic_generator.core.model import (
    DATADOG_SITE,
    Scenario,
    Step,
    StepSummary,
    get_client,
)
from traffic_generator.core.registry import register

if TYPE_CHECKING:
    import httpx

WAF_TRIGGER_ATTEMPTS = 40


class _IngressHealthWafScenario(Scenario):
    waf_rule_id: ClassVar[str]
    waf_attack_type: ClassVar[str]
    product_attack_label: ClassVar[str]
    payload_key: ClassVar[str]
    payload_value: ClassVar[str]

    def before(self) -> None:
        self.public_client: httpx.Client = get_client()

    def after(self) -> None:
        self.public_client.close()

    def steps(self) -> tuple[Step, ...]:
        return (self.trigger_ingress_waf_rule_on_health,)

    def datadog_link(self, *, service_name: str | None) -> str | None:
        if service_name is None:
            return None

        query = quote(
            f"service:{service_name} @appsec.rule_id:{self.waf_rule_id}",
            safe="",
        )
        return (
            f"https://app.{DATADOG_SITE}/security/appsec/investigate/traces"
            f"?query={query}"
        )

    def health_request(self) -> httpx.Response:
        return self.public_client.get(
            "/health",
            params={self.payload_key: self.payload_value},
        )

    def trigger_ingress_waf_rule_on_health(self) -> StepSummary:
        """Generate attack attempts that App and API Protection should detect.

        Send ingress probes through `/health` query input to validate coverage
        for this attack class at request entry.
        """
        non_ok_responses = 0
        for _ in range(WAF_TRIGGER_ATTEMPTS):
            response = self.health_request()
            if response.status_code != HTTPStatus.OK:
                non_ok_responses += 1

        if non_ok_responses:
            return StepSummary(
                outcome="failure",
                summary=(
                    f"`/health` returned non-200 for {non_ok_responses} of "
                    f"{WAF_TRIGGER_ATTEMPTS} requests."
                ),
            )

        return StepSummary(
            outcome="success",
            summary=(
                f"Generated {WAF_TRIGGER_ATTEMPTS} ingress attack attempts on "
                f"`/health`. Datadog App and API Protection can detect attack "
                f"attempts for the {self.product_attack_label} class."
            ),
        )


@register
class HealthSqlInjectionThreatScenario(_IngressHealthWafScenario):
    """Validate SQL injection detection at request ingress."""

    name = "health_waf_sql_injection"
    display_name = "Threat Detection: SQL Injection (/health)"
    waf_rule_id = "crs-942-100"
    waf_attack_type = "sql_injection"
    product_attack_label = "SQL injection"
    payload_key = "probe"
    payload_value = "' OR '1'='1 --"


@register
class HealthXssThreatScenario(_IngressHealthWafScenario):
    """Validate cross-site scripting detection at request ingress."""

    name = "health_waf_xss"
    display_name = "Threat Detection: XSS (/health)"
    waf_rule_id = "crs-941-110"
    waf_attack_type = "xss"
    product_attack_label = "cross-site scripting"
    payload_key = "probe"
    payload_value = "<script>alert('dogfooding')</script>"


@register
class HealthCommandInjectionThreatScenario(_IngressHealthWafScenario):
    """Validate command injection detection at request ingress."""

    name = "health_waf_command_injection"
    display_name = "Threat Detection: Command Injection (/health)"
    waf_rule_id = "crs-932-171"
    waf_attack_type = "command_injection"
    product_attack_label = "command injection"
    payload_key = "probe"
    payload_value = "() { :;}; /bin/bash -c 'id'"


@register
class HealthLfiThreatScenario(_IngressHealthWafScenario):
    """Validate local file inclusion detection at request ingress."""

    name = "health_waf_lfi"
    display_name = "Threat Detection: LFI Path Access (/health)"
    waf_rule_id = "crs-930-120"
    waf_attack_type = "lfi"
    product_attack_label = "local file inclusion"
    payload_key = "probe"
    payload_value = "etc/passwd"
