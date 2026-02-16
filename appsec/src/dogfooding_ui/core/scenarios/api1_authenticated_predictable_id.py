from __future__ import annotations

from http import HTTPStatus

from test_api_client.api.default import (
    api1_sensitive_user_by_predictable_id,
    login,
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

PUBLIC_TEST_SOURCE_IP = "8.8.8.8"
DEFAULT_DEMO_USERNAME = "alice"
DEFAULT_DEMO_PASSWORD = "dogfooding-password"  # noqa: S105
API1_USER_ID_AUTH = 1002


@register
class Api1AuthenticatedPredictableIdScenario(Scenario):
    """Trigger API1 rule def-000-m49 (authenticated predictable object ID access)."""

    name = "api1_authenticated_predictable_id"
    display_name = "API1 Authenticated Predictable ID"
    datadog_link_template = "https://app.datadoghq.com/security/appsec/inventory/apis?query=service:{service_name}"

    def before(self) -> None:
        self.username = DEFAULT_DEMO_USERNAME
        self.password = DEFAULT_DEMO_PASSWORD
        self.access_token: str | None = None
        self.public_client = get_client().with_headers(
            {"X-Forwarded-For": PUBLIC_TEST_SOURCE_IP}
        )

    def after(self) -> None:
        pass

    def steps(self) -> tuple[Step, ...]:
        return (
            self.login_for_api1_session,
            self.read_sensitive_user_by_predictable_id,
        )

    def login_for_api1_session(self) -> StepSummary:
        """Authenticate via `/login` to obtain a bearer token."""
        login_response = login.sync_detailed(
            client=self.public_client,
            username=self.username,
            password=self.password,
        )

        match login_response.parsed:
            case LoginResponse() as response:
                self.access_token = response.access_token
            case None | ErrorResponse() | ValidationErrorResponse() as response:
                return StepSummary(
                    outcome="failure",
                    summary="Could not parse a login token from /login response.",
                )

        return StepSummary(
            outcome="success",
            summary="Authenticated demo user to seed API1 authenticated traffic.",
        )

    def read_sensitive_user_by_predictable_id(self) -> StepSummary:
        """Read sensitive fields from `/api1/users/{user_id}` using predictable ID."""
        if self.access_token is None:
            return StepSummary(
                outcome="failure",
                summary="Cannot call /api1/users/{user_id} without a session token.",
            )

        authed_client = get_authed_client(self.access_token).with_headers(
            {"X-Forwarded-For": PUBLIC_TEST_SOURCE_IP}
        )
        response = api1_sensitive_user_by_predictable_id.sync_detailed(
            API1_USER_ID_AUTH,
            client=authed_client,
        )
        if response.status_code != HTTPStatus.OK:
            return StepSummary(
                outcome="failure",
                summary=(
                    "Could not call GET /api1/users/{user_id} with a session token."
                ),
            )

        return StepSummary(
            outcome="success",
            summary=(
                "Read sensitive data through predictable ID on "
                "authenticated API1 route."
            ),
        )
