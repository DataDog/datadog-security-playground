from __future__ import annotations

import base64
import json
from http import HTTPStatus
from typing import Any
from uuid import uuid4

from test_api_client.api.default import api1_sensitive_user_by_predictable_id

from dogfooding_ui.core.model import (
    Scenario,
    Step,
    StepSummary,
    get_authed_client,
)
from dogfooding_ui.core.registry import register

PUBLIC_TEST_SOURCE_IP = "8.8.8.8"
API1_USER_ID_NO_AUD = 1001


def _encode_compact_json(payload: dict[str, Any]) -> str:
    encoded = json.dumps(
        payload,
        separators=(",", ":"),
        sort_keys=True,
    ).encode("utf-8")
    return base64.urlsafe_b64encode(encoded).decode("utf-8").rstrip("=")


def _build_unsigned_jwt_without_audience(subject: str) -> str:
    header = _encode_compact_json({"alg": "none", "typ": "JWT"})
    claims = _encode_compact_json({"sub": subject})
    return f"{header}.{claims}."


@register
class Api1JwtWithoutAudienceScenario(Scenario):
    """Trigger API1 rule def-000-uo0 (JWT without audience)."""

    name = "api1_jwt_without_audience"
    display_name = "API1 JWT Without Audience"
    datadog_link_template = "https://app.datadoghq.com/security/appsec/inventory/apis?query=service:{service_name}"

    def before(self) -> None:
        pass

    def after(self) -> None:
        pass

    def steps(self) -> tuple[Step, ...]:
        return (self.call_api1_user_lookup_with_no_aud_jwt,)

    def call_api1_user_lookup_with_no_aud_jwt(self) -> StepSummary:
        """Call API1 endpoint with a JWT that omits `aud`.

        Send a no-audience bearer token to `GET /api1/users/{user_id}`.
        """
        token = _build_unsigned_jwt_without_audience(
            subject=f"api1-uo0-{uuid4().hex[:8]}"
        )
        authed_client = get_authed_client(token).with_headers(
            {"X-Forwarded-For": PUBLIC_TEST_SOURCE_IP}
        )
        response = api1_sensitive_user_by_predictable_id.sync_detailed(
            API1_USER_ID_NO_AUD,
            client=authed_client,
        )
        if response.status_code != HTTPStatus.OK:
            return StepSummary(
                outcome="failure",
                summary="Could not call /api1/users/{user_id} with no-aud JWT.",
            )

        return StepSummary(
            outcome="success",
            summary=(
                "Successfully generated no-audience JWT traffic on "
                "GET /api1/users/{user_id}."
            ),
        )
