import functools
import os

import uvicorn

start = functools.partial(
    uvicorn.run,
    "traffic_generator.web.app:app",
    host=os.getenv("DOGFOODING_WEB_HOST", "127.0.0.1"),
    port=int(os.getenv("DOGFOODING_WEB_PORT", "8080")),
)


def main() -> None:
    start(reload=False)


def dev() -> None:
    start(reload=True)
