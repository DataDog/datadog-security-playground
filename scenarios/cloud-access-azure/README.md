# Scenario: Azure Cloud Access — Managed Identity Token Theft and Resource Abuse

## Overview

This scenario simulates an attacker who has gained code execution inside a Kubernetes pod running on AKS and exploits the Azure Instance Metadata Service (IMDS) to steal a managed identity OAuth2 token, then uses that token to attempt unauthorized Azure VM creation across multiple regions.

## Attack Chain

1. **IMDS token theft** — The attacker queries `http://169.254.169.254/metadata/identity/oauth2/token` from inside the pod to obtain a bearer token for the node's managed identity.
2. **Instance metadata enumeration** — Subscription ID, resource group, and region are extracted from `http://169.254.169.254/metadata/instance`.
3. **Resource abuse** — The stolen token is used to call the Azure ARM API (or `az vm create`) to attempt to provision expensive VMs across 8 regions. A non-existent image reference forces the calls to fail, but they still generate Azure Activity Log entries.

## Detection

- **Datadog Cloud Security Management** — Detects the IMDS token request from inside the container and flags it as credential access.
- **Azure Activity Log** — Records the failed `Microsoft.Compute/virtualMachines/write` calls for each region, correlatable in Datadog Cloud SIEM.
- **Datadog Workload Protection** — Flags the `curl` call to the IMDS endpoint as a suspicious process behaviour in a container.

## Prerequisites

- The playground is deployed on AKS using `terraform/aks/` (the node pool has a system-assigned managed identity by default).
- Datadog Agent is running with Cloud Security Management enabled.

## How to Run

```bash
kubectl exec -it -n playground deploy/playground-app -- /scenarios/cloud-access-azure/detonate.sh --wait
```

## Cleanup

No persistent resources are created. The script is removed from the pod at the end of the scenario.
