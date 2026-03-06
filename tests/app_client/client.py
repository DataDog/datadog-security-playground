"""HTTP client for the playground Flask app."""

import requests

DEFAULT_APP_URL = "http://localhost:5000"


class AppClient:
    """HTTP client for the playground Flask app."""

    def __init__(self, base_url: str = DEFAULT_APP_URL):
        self.base_url = base_url

    def inject(self, cmd: str, timeout: float = 60) -> str:
        """Send a command to the /inject endpoint."""
        resp = requests.post(
            f"{self.base_url}/inject",
            data=cmd,
            timeout=timeout,
        )
        resp.raise_for_status()
        return resp.text

    def ping(self, timeout: float = 5) -> bool:
        """Check if the playground app is reachable."""
        try:
            resp = requests.get(f"{self.base_url}/ping", timeout=timeout)
            return resp.status_code == 200
        except requests.RequestException:
            return False
