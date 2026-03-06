"""
Pytest configuration and fixtures for tests.
"""

import logging
import os
import time

import pytest
from rich.logging import RichHandler

from app_client import AppClient
from runtime_security_server import EventServer

# Configure rich logging
logging.basicConfig(
    level=logging.INFO,
    format="%(message)s",
    datefmt="[%X]",
    handlers=[RichHandler(rich_tracebacks=True, show_path=False)],
)
logger = logging.getLogger("tests")

# =============================================================================
# Configuration
# =============================================================================

DEFAULT_SERVER_PORT = 10000
CONNECTION_TIMEOUT = 120  # seconds to wait for system-probe connection
POST_CONNECTION_DELAY = 5  # seconds to wait after connection before tests
DEFAULT_APP_URL = "http://localhost:5000"


# =============================================================================
# Fixtures
# =============================================================================

@pytest.fixture(scope="session")
def test_server():
    """
    Session-scoped gRPC test server that receives security events from the agent.

    Starts before any tests run, waits for system-probe to connect,
    and stops after all tests complete.
    """
    port = int(os.environ.get("TEST_SERVER_PORT", DEFAULT_SERVER_PORT))
    verbose = os.environ.get("TEST_SERVER_VERBOSE", "").lower() in ("1", "true", "yes")
    timeout = float(os.environ.get("CONNECTION_TIMEOUT", CONNECTION_TIMEOUT))

    server = EventServer(port=port, verbose=verbose)
    server.start()

    logger.info(f"Test server started on port {port}")
    logger.info(f"Waiting for system-probe to connect (timeout={timeout}s)...")

    if not server.wait_for_connection(timeout=timeout):
        server.stop()
        pytest.fail(
            f"system-probe did not connect within {timeout}s. "
            f"Make sure the DD Agent is running with runtime security enabled and "
            f"configured to forward events to localhost:{port}"
        )

    delay = float(os.environ.get("POST_CONNECTION_DELAY", POST_CONNECTION_DELAY))
    logger.info(f"system-probe connected, waiting {delay}s before starting tests...")
    time.sleep(delay)

    logger.info("Starting tests")

    yield server

    logger.info(f"Test server stopping (received {server.total_events} total events)")
    server.stop()


@pytest.fixture(scope="session")
def app_client():
    """Session-scoped app HTTP client."""
    url = os.environ.get("APP_URL", DEFAULT_APP_URL)
    client = AppClient(base_url=url)

    if not client.ping():
        pytest.fail(
            f"Playground app is not reachable at {url}. "
            f"Make sure the playground container is running."
        )

    return client
