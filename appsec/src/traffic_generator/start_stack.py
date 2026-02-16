import os

import questionary

APP_FLAVORS: tuple[str, ...] = (
    "python/fastapi",
    "go/gin",
)


def main() -> None:
    selected_flavor = questionary.select(
        message="Select the app flavor profile:",
        choices=list(APP_FLAVORS),
        default=os.getenv("TEST_API_FLAVOR", APP_FLAVORS[0]),
    ).ask()
    if selected_flavor is None:
        raise SystemExit(1)

    command = [
        "docker",
        "compose",
        "--profile",
        selected_flavor,
        "up",
        "--build",
    ]
    os.execvp(command[0], command)  # noqa: S606


if __name__ == "__main__":
    main()
