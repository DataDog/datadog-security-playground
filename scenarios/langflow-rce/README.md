# Langflow CVE-2025-3248 RCE -> Malware + Cloud Credential Theft

## Abstract

This educational security simulation is the **real-exploit alternative** to the
[rce-malware](../rce-malware/) scenario. Instead of driving commands through the
synthetic `/inject` endpoint inside the `playground-app` pod, it runs from the
**attacker's machine** and exploits a genuine vulnerability in the
`langflow-vulnerable` pod:

> **CVE-2025-3248** — unauthenticated remote code execution in Langflow < 1.3.0
> via `POST /api/v1/validate/code` (fixed in 1.3.0).

Once code execution is achieved, the **same downstream payloads** used by the
`rce-malware` and `cloud-access` scenarios are delivered *through the exploit*
onto the langflow pod:

1. a simulated cryptominer with persistence (`assets/rce-malware/payload.sh`)
2. AWS credential theft via IMDS (`assets/cloud-access/retrieve-creds-via-imds.sh`)
3. an attempted EC2 pivot with the stolen creds (`assets/cloud-access/run-instances-with-creds.sh`)

This demonstrates the full kill chain an AI-enabled attacker can automate
against an exposed, vulnerable workload: **discover → exploit → deploy malware →
harvest cloud credentials → attempt lateral movement**.

**⚠️ Important**: This is a simulation using harmless demo binaries for
educational purposes only. The cryptominer is fake and the EC2 launches use an
invalid AMI so they never succeed.

## How it differs from `rce-malware`

| | `rce-malware` | `langflow-rce` (this scenario) |
|---|---|---|
| Runs from | inside `playground-app` pod | the attacker's laptop |
| Initial access | synthetic `/inject` endpoint | real CVE-2025-3248 exploit |
| Target | `localhost:5000` | `http://langflow-demo:7860` (the langflow pod) |
| Downstream payloads | `rce-malware/payload.sh` | same, delivered via the exploit |
| Recon phase | none | nmap / httpx / nuclei (if installed) |
| Cloud pivot | separate `cloud-access` scenario | chained in the same run |

## Prerequisites

On the attacker machine:

- `python3` and the `requests` package (`pip install requests`)
- `kubectl` access to the playground cluster
- An `/etc/hosts` entry mapping `langflow-demo` to `127.0.0.1` (or pass
  `--target http://localhost:7860`)
- Recon tools are optional: `nmap`, `httpx`, `nuclei`. Any that are missing are
  skipped with a notice (the demo still runs).

### Setup (port-forward the vulnerable pod)

```bash
# port-forward the vulnerable langflow pod to localhost:7860
kubectl port-forward -n playground deployment/langflow-vulnerable 7860:7860

# (optional) add a hosts entry so http://langflow-demo:7860 resolves
echo "127.0.0.1 langflow-demo" | sudo tee -a /etc/hosts
```

## How to Run

```bash
# From the repo root, on the attacker machine:
./scenarios/langflow-rce/detonate.sh --wait

# Or against an explicit target, auto-running all steps:
./scenarios/langflow-rce/detonate.sh --target http://localhost:7860

# Pin payload downloads to a specific git ref (defaults to main):
./scenarios/langflow-rce/detonate.sh --ref $(git rev-parse HEAD)
```

### Options

| Flag | Description |
|------|-------------|
| `-w, --wait` | Wait for Enter between each step (recommended for live demos) |
| `-s, --silent` | No talk-track; exploit output suppressed (for automation) |
| `-t, --target URL` | Langflow target URL (default: `http://langflow-demo:7860`) |
| `-r, --ref REF` | Git ref for payload downloads (default: `main`) |
| `-e, --exploit PATH` | Path to `CVE-2025-3248.py` (default: vendored copy in `assets/langflow-rce/`) |

Environment variable overrides: `LANGFLOW_TARGET`, `PLAYGROUND_REF`,
`CVE_EXPLOIT`.

## Attack Flow

1. **Reconnaissance** — `nmap` discovers ports, `httpx` confirms Langflow,
   `nuclei` verifies CVE-2025-3248.
2. **Exploit sanity checks** — `whoami`, `ls -al /`, and a deliberately failing
   command confirm reliable command execution with reflected output.
3. **Tool installation** — ensure `curl` is present on the compromised pod.
4. **Malware deployment** — download & run `assets/rce-malware/payload.sh`
   (simulated cryptominer + persistence).
5. **Credential theft** — download & run
   `assets/cloud-access/retrieve-creds-via-imds.sh` (IMDS credential harvest).
6. **Lateral movement** — download & run
   `assets/cloud-access/run-instances-with-creds.sh` (attempted EC2 pivot).
7. **Cleanup** — kill the miner and remove all downloaded artifacts.

## Detection

This scenario generates the same Datadog Workload Protection signals as the
`rce-malware` and `cloud-access` scenarios (cryptominer args, mining-pool DNS
lookups, persistence via `rc.common` / `authorized_keys`, IMDS access,
executable bit added, new binary execution, etc.), **plus** an AppSec signal for
the CVE-2025-3248 exploit attempt on `POST /api/v1/validate/code` (the
langflow-vulnerable pod runs with `DD_APPSEC_ENABLED=true`).

> **Note**: Unlike the in-pod scenarios, this one is **not** covered by the
> `tests/` pytest harness, which drives the `playground-app` `/inject`
> endpoint against a local runtime-security server. This scenario requires the
> real `langflow-vulnerable` pod and the external exploit, so it is run
> manually from the attacker machine.

## Exploit provenance

The `CVE-2025-3248.py` PoC is vendored under `assets/langflow-rce/` so the
scenario is self-contained and reproducible. The only change versus upstream is
a `--quiet` flag (and `CVE_QUIET` env var) that suppresses the spinner and ASCII
banner so the chained driver can invoke it many times without re-printing. The
exploit logic and attribution are unchanged.

- Upstream: <https://github.com/verylazytech/CVE-2025-3248>
- Metasploit module: <https://github.com/rapid7/metasploit-framework/blob/master/modules/exploits/multi/http/langflow_unauth_rce_cve_2025_3248.rb>
- Original author: EQST (Experts, Qualified Security Team)
