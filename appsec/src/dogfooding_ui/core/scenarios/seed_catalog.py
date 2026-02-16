from http import HTTPStatus
from uuid import uuid4

from test_api_client.api.default import (
    health,
    login,
    signup,
    whoami,
)
from test_api_client.models import (
    ErrorResponse,
    LoginResponse,
    ValidationErrorResponse,
)

from dogfooding_ui.core.model import (
    Scenario,
    Step,
    StepSummary,
    get_authed_client,
    get_client,
)
from dogfooding_ui.core.registry import register

ATTEMPTS = 100

PUBLIC_TEST_SOURCE_IP = "8.8.8.8"
SSRF_PAYLOADS = [
    "http://169.254.169.254/latest/meta-data/iam/security-credentials/",
    "http://127.0.0.1:2375/containers/json",
    "file:///etc/passwd",
] * 30
SQLI_PAYLOADS = [
    "' OR '1'='1",
    "'; DROP TABLE users; --",
    "' UNION SELECT password FROM users --",
] * 30


@register
class SeedCatalogScenario(Scenario):
    """Populate the App and API Protection Endpoint Catalog.

    Seed the API endpoint catalog with normal account/session activity and
    SSRF and SQL injection attack attempts to make AppSec views richer.
    """

    name = "seed_catalog"
    display_name = "Catalog Seeding"
    datadog_link_template = "https://app.{dd_site}/security/appsec/inventory/apis?query=service:{service_name}"

    def before(self) -> None:
        self.public_client = get_client().with_headers(
            {"X-Forwarded-For": PUBLIC_TEST_SOURCE_IP}
        )

    def after(self) -> None:
        pass

    def steps(self) -> tuple[Step, ...]:
        return (
            self.seed_catalog_with_user_journeys,
            self.perform_ssrf_attack_attempts,
            self.perform_sql_injection_attack_attempts,
        )

    def seed_catalog_with_user_journeys(
        self,
    ) -> StepSummary:
        """Seed endpoints using the ATO SDK.

        Create unique users and exercise signup, login, whoami, and health
        endpoints across repeated flows.
        """
        for _ in range(ATTEMPTS):
            username = f"catalog-user-{uuid4().hex[:8]}"
            user_password = f"secret-{uuid4().hex}"
            r = health.sync_detailed(client=self.public_client)
            if r.status_code != HTTPStatus.OK:
                return StepSummary(outcome="failure", summary="Test API is unhealthy.")

            r = signup.sync_detailed(
                client=self.public_client,
                username=username,
                password=user_password,
            )
            if r.status_code != HTTPStatus.OK:
                return StepSummary(outcome="failure", summary="Could not signup.")

            login_response = login.sync_detailed(
                client=self.public_client,
                username=username,
                password=user_password,
            )
            if login_response.status_code != HTTPStatus.OK:
                return StepSummary(outcome="failure", summary="Could not login.")

            match login_response.parsed:
                case LoginResponse() as response:
                    access_token = response.access_token
                case None | ErrorResponse() | ValidationErrorResponse() as response:
                    break

            with get_authed_client(access_token) as authed_client:
                r = whoami.sync_detailed(client=authed_client)
                if r.status_code != HTTPStatus.OK:
                    return StepSummary(
                        outcome="failure", summary="Could not get /whoami."
                    )

        return StepSummary(
            outcome="success",
            summary="Successfully generated traffic on routes using the ATO  SDK",
        )

    def perform_ssrf_attack_attempts(
        self,
    ) -> StepSummary:
        """Perform SSRF attack attemps.

        Send URL-style payloads to `/login` so telemetry captures SSRF-like
        requests
        """
        for attempt_index, target_url in enumerate(SSRF_PAYLOADS):
            login.sync_detailed(
                client=self.public_client,
                username=target_url,
                password=f"ssrf-probe-{attempt_index}",
            )

        return StepSummary(
            outcome="success",
            summary="Successfully generated some SSRF attack attempts.",
        )

    def perform_sql_injection_attack_attempts(
        self,
    ) -> StepSummary:
        """Perform SQL injection attack attempts through existing auth endpoint.

        Send SQL-style payloads to `/login` so telemetry captures injection
        attempts
        """
        for attempt_index, payload in enumerate(SQLI_PAYLOADS):
            login.sync_detailed(
                client=self.public_client,
                username=payload,
                password=f"sqli-probe-{attempt_index}",
            )

        return StepSummary(
            outcome="success",
            summary="Successfully generated some SQLi attack attempts",
        )
