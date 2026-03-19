import os
import subprocess
import sys
import webbrowser

import questionary

APP_FLAVORS: tuple[str, ...] = (
    "python/fastapi",
    "go/gin",
)
DOGFOODING_URL = "http://localhost:8080/dogfooding"


def run_command(command: list[str], *, check: bool = True) -> None:
    subprocess.run(  # noqa: S603
        command,
        check=check,
        stdin=sys.stdin,
        stdout=sys.stdout,
        stderr=sys.stderr,
    )


def main() -> None:
    selected_flavor = questionary.select(
        message="Select the app flavor profile:",
        choices=list(APP_FLAVORS),
        default=os.getenv("TEST_API_FLAVOR", APP_FLAVORS[0]),
    ).ask()
    if selected_flavor is None:
        raise SystemExit(1)

    compose_command = [
        "docker",
        "compose",
        "--profile",
        selected_flavor,
    ]
    should_shutdown = False

    try:
        should_shutdown = True
        run_command([*compose_command, "up", "--build", "--detach"])
        webbrowser.open_new_tab(DOGFOODING_URL)
        run_command([*compose_command, "logs", "--follow"])
    except KeyboardInterrupt:
        if should_shutdown:
            run_command([*compose_command, "down"], check=False)
        raise SystemExit(130) from None
    except subprocess.CalledProcessError:
        if should_shutdown:
            run_command([*compose_command, "down"], check=False)
        raise


if __name__ == "__main__":
    main()
