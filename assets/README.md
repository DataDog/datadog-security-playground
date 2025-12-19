# Assets Directory

This directory contains the assets used by the different detonation scenarios of the Datadog Security Playground.

## Structure

- **`bpfdoor/`** : Contains the source code and binaries to simulate a BPFDoor attack
  - `fake-bpfdoor.c` : C source code of the BPFDoor simulator
  - `fake-bpfdoor.x64` : Compiled binary for x64 architecture
  - `build.sh` : Build script for the BPFDoor binary

- **`malware/`** : Contains the source code and binaries to simulate a cryptocurrency mining malware attack
  - `main.go` : Go source code of the malware simulator
  - `malware.x64` : Compiled binary for x64 architecture
  - `malware.arm64` : Compiled binary for ARM64 architecture
  - `build.sh` : Build script for the malware binaries

- **`correlation/`** : Contains the script to run the threats correlation and attack chain demonstration
  - `payload.sh` : First stage of the attack, retrieved by exploiting the playground app

## Building Binaries

The Makefile uses Docker to build binaries in a reproducible environment:

```bash
make all
```

This will:
1. Build a Docker image with all necessary build tools (gcc, Go toolchain)
2. Compile all binaries in build containers
3. Automatically extract the binaries to their respective directories

**Other Make targets:**

```bash
make clean    # Remove Docker image
make rebuild  # Remove the Docker image and rebuild everything
make help     # Show available targets
```

## ⚠️ Important

These binaries are **educational simulators** and cause no real damage. They are designed solely to demonstrate Datadog Workload Protection detection capabilities in a controlled environment.

