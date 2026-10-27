from http import HTTPStatus
from typing import TYPE_CHECKING
from urllib.parse import quote
from uuid import uuid4

from traffic_generator.core.model import (
    DATADOG_SITE,
    Scenario,
    Step,
    StepSummary,
    get_client,
    random_public_ipv4,
)
from traffic_generator.core.registry import register

if TYPE_CHECKING:
    import httpx

# `appsec-ato-groupby-ip` (Credential Stuffing attack) groups login failures by
# IP over a 1h window. Its lowest case needs `failed_login_by_ip > 30` and
# `user_count >= 5` distinct usernames; the critical "account compromised" case
# additionally needs one successful login from the same IP, with failures still
# above 5x successes. Attack enough distinct users to clear every threshold.
CREDENTIAL_STUFFING_ATTEMPTS = 60
FAILED_LOGIN_THRESHOLD = 30
# Seeded demo accounts the attacker would hit with leaked-password guesses.
KNOWN_USERNAMES = ("alice", "bob")
# One seeded account whose real password the attacker "knows" from the dump, so
# a single guess lands and the detection escalates to account compromise.
COMPROMISED_USERNAME = "alice"
DEMO_PASSWORD = "dogfooding-password"  # noqa: S105


@register
class CredentialStuffingAtoScenario(Scenario):
    """Validate account takeover detection for credential stuffing.

    Replay failed logins across many distinct usernames from a single source IP,
    then land one valid login, so the `appsec-ato-groupby-ip` rule groups the
    login failures and signals an account compromised by credential stuffing.
    """

    name = "ato_credential_stuffing"
    display_name = "ATO: Credential Stuffing (/login)"
    # Own IP so logins from other scenarios do not dilute the failure/success ratio.
    source_ip = random_public_ipv4()

    def before(self) -> None:
        self.public_client: httpx.Client = get_client(
            headers={"X-Forwarded-For": self.source_ip}
        )

    def after(self) -> None:
        self.public_client.close()

    def steps(self) -> tuple[Step, ...]:
        return (self.replay_failed_logins, self.compromise_known_account)

    def datadog_link(self, *, service_name: str | None) -> str | None:
        terms = [f"@http.client_ip:{self.source_ip}"]
        if service_name is not None:
            terms.append(f"service:{service_name}")
        query = quote(" ".join(terms), safe="")
        return (
            f"https://app.{DATADOG_SITE}/security/appsec/investigate/attackers"
            f"?column=count&fromUser=false&group=ip&query={query}"
        )

    def attack_usernames(self) -> tuple[str, ...]:
        random_users = tuple(
            f"stuffed-{uuid4().hex[:8]}"
            for _ in range(CREDENTIAL_STUFFING_ATTEMPTS - len(KNOWN_USERNAMES))
        )
        return KNOWN_USERNAMES + random_users

    def replay_failed_logins(self) -> StepSummary:
        """Replay failed logins across many usernames from one IP.

        Send `/login` attempts with leaked-style wrong passwords so App and API
        Protection records the login failures the ATO rule groups by IP.
        """
        failures = sum(
            self.public_client.post(
                "/login",
                params={"username": username, "password": f"leaked-{uuid4().hex}"},
            ).status_code
            == HTTPStatus.FORBIDDEN
            for username in self.attack_usernames()
        )

        if failures <= FAILED_LOGIN_THRESHOLD:
            return StepSummary(
                outcome="failure",
                summary=(
                    f"Only {failures} of {CREDENTIAL_STUFFING_ATTEMPTS} logins failed. "
                    f"The ATO rule needs more than {FAILED_LOGIN_THRESHOLD}."
                ),
            )

        return StepSummary(
            outcome="success",
            summary=(
                f"Replayed {failures} failed logins across distinct usernames from "
                f"`{self.source_ip}`. Datadog groups these by IP to detect a "
                f"credential stuffing attack."
            ),
        )

    def compromise_known_account(self) -> StepSummary:
        """Land one valid login to complete the account takeover.

        Log in as a seeded account with its real password so the ATO rule sees a
        successful login from the attacking IP and escalates to account compromise.
        """
        response = self.public_client.post(
            "/login",
            params={"username": COMPROMISED_USERNAME, "password": DEMO_PASSWORD},
        )
        if response.status_code != HTTPStatus.OK:
            return StepSummary(
                outcome="failure",
                summary=f"Could not log in as `{COMPROMISED_USERNAME}`.",
            )

        return StepSummary(
            outcome="success",
            summary=(
                f"Compromised `{COMPROMISED_USERNAME}` from `{self.source_ip}`. "
                f"Datadog can detect this as an account compromised by credential "
                f"stuffing."
            ),
        )
