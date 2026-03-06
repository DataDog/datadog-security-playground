"""
Event Server - gRPC server that receives security events from the DD Agent
and stores them for test verification.
"""

import json
import logging
import threading
from concurrent import futures
from dataclasses import dataclass
from typing import Any

import grpc
from google.protobuf import empty_pb2

from runtime_security_server.grpc_gen import api_pb2_grpc

logger = logging.getLogger("runtime-security-server")


@dataclass
class StoredEvent:
    """An event stored for verification."""
    rule_id: str
    data: dict[str, Any]
    tags: list[str]
    timestamp: Any

    @classmethod
    def from_proto(cls, request, data: dict) -> "StoredEvent":
        return cls(
            rule_id=request.RuleID,
            data=data,
            tags=list(request.Tags),
            timestamp=request.Timestamp,
        )


class EventStore:
    """Thread-safe storage for all received events."""

    def __init__(self):
        self._events: list[StoredEvent] = []
        self._lock = threading.Lock()

    def add_event(self, event: StoredEvent) -> None:
        with self._lock:
            self._events.append(event)

    @property
    def total_events(self) -> int:
        with self._lock:
            return len(self._events)

    def get_all_events(self) -> list[StoredEvent]:
        with self._lock:
            return list(self._events)

    def get_rule_ids(self) -> set[str]:
        with self._lock:
            return {e.rule_id for e in self._events}

class TestServicer(api_pb2_grpc.SecurityAgentAPIServicer):
    """gRPC servicer that stores events for test verification."""

    def __init__(
        self,
        event_store: EventStore,
        connection_event: threading.Event,
        verbose: bool = False,
    ):
        self.event_store = event_store
        self.connection_event = connection_event
        self.verbose = verbose
        self._connected = False

    def SendEvent(self, request_iterator, context):
        if not self._connected:
            self._connected = True
            self.connection_event.set()
            if self.verbose:
                logger.info("Client connected")

        for request in request_iterator:
            try:
                data = json.loads(request.Data)
                event = StoredEvent.from_proto(request, data)
                self.event_store.add_event(event)

                if self.verbose:
                    logger.debug(f"Event: rule={event.rule_id}")

            except json.JSONDecodeError as e:
                if self.verbose:
                    logger.warning(f"Failed to parse event data: {e}")
                continue

        return empty_pb2.Empty()

    def SendActivityDumpStream(self, request_iterator, context):
        return empty_pb2.Empty()


class EventServer:
    """
    gRPC test server that receives security events from the DD Agent.

    Usage:
        server = EventServer(port=10000)
        server.start()
        server.wait_for_connection(timeout=120)
        # ... run tests ...
        server.stop()
    """

    def __init__(self, port: int = 10000, verbose: bool = False):
        self.port = port
        self.verbose = verbose
        self.event_store = EventStore()
        self._server: grpc.Server | None = None
        self._started = False
        self._connection_event = threading.Event()

    def start(self) -> None:
        if self._started:
            return

        self._server = grpc.server(futures.ThreadPoolExecutor(max_workers=10))
        servicer = TestServicer(
            self.event_store,
            self._connection_event,
            verbose=self.verbose,
        )
        api_pb2_grpc.add_SecurityAgentAPIServicer_to_server(servicer, self._server)
        self._server.add_insecure_port(f"[::]:{self.port}")
        self._server.start()
        self._started = True

        if self.verbose:
            logger.info(f"Started on port {self.port}")

    def wait_for_connection(self, timeout: float = 60.0) -> bool:
        if self.verbose:
            logger.info(f"Waiting for client connection (timeout={timeout}s)...")

        connected = self._connection_event.wait(timeout=timeout)

        if connected and self.verbose:
            logger.info("Client connected, ready for tests")

        return connected

    def stop(self, grace: float = 5.0) -> None:
        if self._server and self._started:
            self._server.stop(grace=grace)
            self._started = False
            if self.verbose:
                logger.info(f"Stopped (received {self.event_store.total_events} events)")

    @property
    def total_events(self) -> int:
        return self.event_store.total_events
