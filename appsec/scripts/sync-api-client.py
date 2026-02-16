#!/usr/bin/env -S uv run --locked
# /// script
# requires-python = ">=3.14"
# dependencies = [
#   "openapi-python-client>=0.28.2",
# ]
# ///
import subprocess


def main() -> None:
    subprocess.run(
        [  # noqa: S607
            "openapi-python-client",
            "generate",
            "--path=test_api/openapi.yaml",
            "--config=openapi-client-config.yaml",
            "--meta=uv",
            "--output-path=src/test_api_client",
            "--overwrite",
        ],
        check=True,
    )


if __name__ == "__main__":
    main()
