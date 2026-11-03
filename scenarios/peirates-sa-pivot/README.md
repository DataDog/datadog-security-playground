# peirates-sa-pivot

Executes the workload-to-node privilege-escalation chain with the real
[peirates](https://github.com/inguardians/peirates) tool, assuming the attacker
already has code execution in the `langflow-vulnerable` pod (e.g. via the
[langflow-rce](../langflow-rce/) scenario):

1. Over-grants the workload SA (`playground:default`) with pod
   `get/list/create/delete` + `pods/exec` permissions (`manifest.yaml`)
2. Stages the official peirates release binary into the pod
3. `list-secrets` — denied (secrets permissions are never granted)
4. Outbound connect to port 22 on a node — together with the peirates exec
   (and under the same kubectl-exec session correlation key) this fires the
   `reconnaissance_and_access` lateral movement correlation
   (`offensive_k8s_tool` + `ssh_outbound_connection`)
5. `attack-pod-hostpath-mount` — the SA creates a hostPath pod mounting the
   node root, appends a reverse-shell cron line to the host `/etc/crontab`,
   deletes the pod
6. A second hostPath pod (via peirates' embedded kubectl, running as a different
   SA — `playground-sa` — so the audit events show the workload SA creating a
   pod with another identity) writes a marker file (`/etc/PWNED-BY-PEIRATES`)
   into the host's `/etc`
7. Verifies the host artifacts on every node, then fully restores:
   host files (a pre-existing crontab is never touched), attack/debug pods,
   the RBAC grant and the staged binary

The planted cron callback points at `127.0.0.1:4444` (inert) and Amazon Linux
nodes ship no crond, so the persistence line never fires.

## Run

```bash
python3 scenarios/peirates-sa-pivot/detonate.py --wait    # step-by-step
python3 scenarios/peirates-sa-pivot/detonate.py            # auto-run
python3 scenarios/peirates-sa-pivot/detonate.py --dry-run  # print commands only
```

Prerequisites: `kubectl` configured for the playground cluster, the
`langflow-vulnerable` deployment running in the `playground` namespace, and
internet access to download the peirates release.

Flags: `-w/--wait`, `-s/--silent`, `-n/--namespace` (default `playground`),
`--dry-run`. Shared helpers: [`scripts/k8s_tool.py`](../../scripts/k8s_tool.py).
