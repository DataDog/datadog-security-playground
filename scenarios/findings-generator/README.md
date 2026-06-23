# Essential Linux Binary Modified - Findings Generator

- **Location**: `scenarios/findings-generator/`
- **Description**: Essential system binaries in containers are executable files that perform operating system functions and administrative tasks. These binaries typically reside in protected system directories such as `/bin`, `/sbin`, `/usr/bin`, and `/usr/sbin`. In containerized environments, these binaries are part of the container image layers and should be immutable during runtime.
- **Attack Vector**: File system modifications to critical binaries
- **Impact**: Demonstrates detection of unauthorized changes to system binaries including download third party binaries, permission changes, ownership modifications, file renames, deletions, and timestamp tampering
- **Detection**: Workload Protection findings for Essential Linux binary modified in container (PCI DSS 11.5 compliance)
- **Operations**: chmod, chown, link, rename, open/modify, unlink, and utimes operations

## How to Run

```bash
# Execute all file operations (recommended)
kubectl exec -it -n playground deploy/playground-app -- /scenarios/findings-generator/detonate.sh

# Or run a specific operation
kubectl exec -it -n playground deploy/playground-app -- /scenarios/findings-generator/detonate.sh [chmod|chown|link|rename|open|unlink|utimes]
```
