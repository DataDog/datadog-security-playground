from http import HTTPStatus
from typing import TYPE_CHECKING, cast
from uuid import uuid4

from traffic_generator.core.model import (
    Scenario,
    Step,
    StepSummary,
    get_authed_client,
    get_client,
)
from traffic_generator.core.registry import register

if TYPE_CHECKING:
    import httpx

ATTEMPTS = 100


@register
class ApmTrafficScenario(Scenario):
    """Generate baseline API traffic."""

    name = "apm_traffic"
    display_name = "Benign Traffic generation"
    datadog_link_template = "https://app.{dd_site}/security/appsec/inventory/apis?query=service:{service_name}"

    def before(self) -> None:
        self.public_client: httpx.Client = get_client()

    def after(self) -> None:
        self.public_client.close()

    def steps(self) -> tuple[Step, ...]:
        return (self.seed_catalog_with_user_journeys,)

    def seed_catalog_with_user_journeys(
        self,
    ) -> StepSummary:
        """Generate baseline account and session traffic.

        Exercise signup, login, and authenticated profile routes so App and API
        Protection can populate endpoint inventory and baseline behavior.
        """
        for _ in range(ATTEMPTS):
            username = f"catalog-user-{uuid4().hex[:8]}"
            user_password = f"secret-{uuid4().hex}"
            r = self.public_client.get("/health")
            if r.status_code != HTTPStatus.OK:
                return StepSummary(outcome="failure", summary="Test API is unhealthy.")

            r = self.public_client.post(
                "/signup",
                params={"username": username, "password": user_password},
            )
            if r.status_code != HTTPStatus.OK:
                return StepSummary(outcome="failure", summary="Could not signup.")

            login_response = self.public_client.post(
                "/login",
                params={"username": username, "password": user_password},
            )
            if login_response.status_code != HTTPStatus.OK:
                return StepSummary(outcome="failure", summary="Could not login.")

            try:
                login_payload = login_response.json()
            except ValueError:
                break
            if not isinstance(login_payload, dict):
                break
            login_payload_object = cast("dict[str, object]", login_payload)
            access_token = login_payload_object.get("access_token")
            if not isinstance(access_token, str) or not access_token:
                break

            with get_authed_client(access_token) as authed_client:
                r = authed_client.get("/whoami")
                if r.status_code != HTTPStatus.OK:
                    return StepSummary(
                        outcome="failure", summary="Could not get /whoami."
                    )

        return StepSummary(
            outcome="success",
            summary=(
                "Generated baseline user journey traffic so App and API Protection "
                "can map API endpoints and normal usage."
            ),
        )
