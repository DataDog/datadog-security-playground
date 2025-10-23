# Assets Directory

This directory contains the assets used by the different detonation scenarios of the Datadog Security Playground.

## Structure

- **`fake-bpfdoor/`** : Contains the source code and binaries to simulate a BPFDoor attack
  - `fake-bpfdoor.c` : C source code of the BPFDoor simulator
  - `fake-bpfdoor.x64` : Compiled binary for x64 architecture
  - `Makefile` : Build script for the BPFDoor binary

- **`malware/`** : Contains the source code and binaries to simulate a cryptocurrency mining malware attack
  - `main.go` : Go source code of the malware simulator
  - `malware.x64` : Compiled binary for x64 architecture
  - `malware.arm64` : Compiled binary for ARM64 architecture
  - `Makefile` : Build script for the malware binaries

- **`correlation/`** : Contains the script to run the threats correlation and attack chain demonstration
  - `payload.sh` : First stage of the attack, retrieved by exploiting the playground app

## Building Binaries

To rebuild all binaries from both directories, use the root Makefile:

```bash
make
```

Or to rebuild individually:

```bash
# For the BPFDoor simulator
make fake-bpfdoor

# For the malware simulator
make malware
```

## ⚠️ Important

These binaries are **educational simulators** and cause no real damage. They are designed solely to demonstrate Datadog Workload Protection detection capabilities in a controlled environment.

