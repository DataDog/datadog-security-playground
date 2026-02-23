# AI Guard Playground

The **AI Security** tab in the Security Playground provides an interactive interface to evaluate prompts against [Datadog AI Guard](https://docs.datadoghq.com/security/ai_security/ai_guard/).

## Overview

AI Guard evaluates LLM interactions (system prompt + user input) and returns an assessment outcome:

| Outcome | Meaning |
|---------|---------|
| `ALLOW` | Interaction appears safe — no issues detected |
| `DENY`  | Interaction flagged — enforcement depends on configuration |
| `ABORT` | Interaction blocked by the SDK (`AIGuardAbortError` raised) |

These are **assessment results**, not automatic enforcement actions. Actual blocking requires both a blocking rule configured in the AI Guard UI and `block=True` set in the SDK.

## How It Works

The `/llm` endpoint sends the system prompt and user message to AI Guard via the ddtrace SDK:

```python
from ddtrace.appsec.ai_guard import AIGuardAbortError, Message, Options, new_ai_guard_client

client = new_ai_guard_client()
result = client.evaluate(messages=messages, options=Options(block=True))
```

If a blocking rule is active and the interaction is flagged, the SDK raises `AIGuardAbortError`. The application must catch and handle this exception — AI Guard does not automatically stop downstream execution.

## Scenarios

The playground includes 14 pre-built scenarios covering common AI attack vectors:

| Scenario | Description |
|----------|-------------|
| Clean Prompt | Benign interaction — expected to be allowed |
| Bootstrap Poisoning | Inject malicious commands into shell init files |
| CI Pivot | Exfiltrate secrets via CI/CD workflow modification |
| Dependency Poisoning | Add malicious `postinstall` scripts to `package.json` |
| Friendly (Hidden Injection) | Prompt injection hidden inside legitimate-looking content |
| Global Memory Poisoning | Persist malicious instructions across agent sessions |
| Guard Tamper | Disable AI Guard hooks and configuration |
| Incremental Escalation | Multi-step privilege escalation chain |
| Localhost Pivot | Access cloud metadata and exfiltrate via SSRF |
| PATH Hijack | Override PATH to execute attacker-controlled binaries |
| Publisher Compromise | Install malicious plugin with root post-install commands |
| Symlink Traversal | Write sensitive files via symlink outside project root |
| Tool Output Injection | Inject malicious instructions via tool call output |
| Unicode Obfuscation | Use Unicode control characters to hide malicious commands |

## Setup

Requires the following environment variables (see `.env.example`):

```bash
DD_API_KEY=your_datadog_api_key
DD_APP_KEY=your_datadog_app_key
DD_SITE=datadoghq.com
DD_ENV=playground
DD_SERVICE=ai-guard-playground
```
