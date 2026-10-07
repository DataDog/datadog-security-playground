"""HTTP client for the playground Flask app."""

import time

import requests

DEFAULT_APP_URL = "http://localhost:5000"


class AppClient:
    """HTTP client for the playground Flask app."""

    def __init__(self, base_url: str = DEFAULT_APP_URL):
        self.base_url = base_url

    def inject(self, cmd: str, timeout: float = 60, attempts: int = 5, retry_delay: float = 1.0) -> str:
        """Send a command to the /inject endpoint.

        The app can drop the request body under rapid back-to-back calls, which the endpoint
        answers with 4xx/5xx; retry so a transient drop does not silently skip the command.
        """
        last_error: Exception | None = None
        for _ in range(attempts):
            try:
                resp = requests.post(f"{self.base_url}/inject", data=cmd, timeout=timeout)
                resp.raise_for_status()
                return resp.text
            except requests.RequestException as error:
                last_error = error
                time.sleep(retry_delay)
        raise RuntimeError(f"/inject did not accept the command after {attempts} attempts: {cmd[:80]}") from last_error

    def ping(self, timeout: float = 5) -> bool:
        """Check if the playground app is reachable."""
        try:
            resp = requests.get(f"{self.base_url}/ping", timeout=timeout)
            return resp.status_code == 200
        except requests.RequestException:
            return False
