"""Generate gRPC Python stubs from api.proto and fix import paths."""

import subprocess
import sys
from pathlib import Path

PACKAGE = "runtime_security_server"

# Directories relative to this script
SCRIPT_DIR = Path(__file__).parent
PROTO_DIR = SCRIPT_DIR / "proto"
OUT_DIR = SCRIPT_DIR / "grpc_gen"

# Import path replacements applied to generated files
REPLACEMENTS = {
    "api_pb2_grpc.py": [
        ("import api_pb2 as api__pb2", f"from {PACKAGE}.grpc_gen import api_pb2 as api__pb2"),
        ("api_pb2_grpc.py", f"{PACKAGE}/grpc_gen/api_pb2_grpc.py"),
    ],
    "api_pb2.py": [
        ("'api_pb2'", f"'{PACKAGE}.grpc_gen.api_pb2'"),
    ],
}


def generate() -> None:
    proto_file = PROTO_DIR / "api.proto"
    if not proto_file.exists():
        print(f"Error: {proto_file} not found", file=sys.stderr)
        sys.exit(1)

    OUT_DIR.mkdir(parents=True, exist_ok=True)

    print(f"Generating gRPC stubs from {proto_file}...")
    subprocess.run(
        [
            sys.executable, "-m", "grpc_tools.protoc",
            f"-I{PROTO_DIR}",
            f"--python_out={OUT_DIR}",
            f"--grpc_python_out={OUT_DIR}",
            str(proto_file),
        ],
        check=True,
    )

    # Fix import paths in generated files
    for filename, replacements in REPLACEMENTS.items():
        filepath = OUT_DIR / filename
        if not filepath.exists():
            print(f"Warning: {filepath} not found, skipping", file=sys.stderr)
            continue

        content = filepath.read_text()
        for old, new in replacements:
            content = content.replace(old, new)
        filepath.write_text(content)
        print(f"  Fixed imports in {filename}")

    print("Done.")


if __name__ == "__main__":
    generate()
