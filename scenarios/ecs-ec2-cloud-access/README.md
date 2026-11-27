# ECS EC2 RCE → Task Credential Theft → Attempted EC2 Launch (Task-ID Correlation)

## Abstract

This scenario is the **ECS on EC2** variant of the `cloud-access` and `rce-malware`
chains. It runs from the attacker's machine against the `playground-app` container
of the [`terraform/ecs-ec2`](../../terraform/ecs-ec2/) cluster, through the same
synthetic `/inject` RCE shim the in-cluster scenarios use, but reached over an
SSM port-forward instead of `kubectl exec`.

Once code execution is achieved, the chain:

1. deploys the simulated cryptominer (persistence in `~/.ssh/authorized_keys` and
   `/etc/rc.common`, `LD_PRELOAD` mining-pool DNS),
2. steals AWS credentials **twice**: the instance profile via IMDS
   (`169.254.169.254`) *and* the **task role via the ECS credential endpoint**
   (`169.254.170.2$AWS_CONTAINER_CREDENTIALS_RELATIVE_URI`),
3. attempts to launch EC2 instances across 8 regions with the stolen **task-role**
   credentials. The task role denies everything and the payload uses an invalid
   AMI, so every attempt fails — but each one is recorded in CloudTrail,
   **attributed to the ECS task ID**.

The point of the scenario is the correlation story: the ECS agent mints task-role
credentials with the **task ID as the role session name**, so every CloudTrail
event made with the stolen credentials carries the task ID, and the runtime
(CWS) signals from the compromised container are grouped under the agent's
`cgroup_*` correlation key — one task ID ties the whole kill chain together.

**⚠️ Important**: This is a simulation using harmless demo binaries. The
cryptominer is fake, the AMI is invalid, and the task role denies every action.

## How it differs from `cloud-access` / `langflow-rce`

| | `cloud-access` | `langflow-rce` | this scenario |
|---|---|---|---|
| Runs from | inside `playground-app` pod (k8s) | the attacker's laptop | the attacker's laptop |
| Initial access | `/inject` via `kubectl exec` | real CVE-2025-3248 exploit | `/inject` via SSM port-forward |
| Stolen credentials | IMDS (instance profile) | IMDS (instance profile) | IMDS **+ ECS task credential endpoint** (task role) |
| CloudTrail attribution | instance ID (session name) | instance ID | **ECS task ID** (session name) |
| Severity target | n/a | full chain | tuned to **high** (see below) |

## Prerequisites

- The [`terraform/ecs-ec2`](../../terraform/ecs-ec2/) stack applied. The app task
  definition ships with a **deny-all task role** (`<cluster>-app-task-role`) so
  stolen task credentials are task-attributable in CloudTrail but can never do
  anything.
- AWS CLI with SSM access to the cluster's container instance
  (`aws ecs describe-clusters` / `terraform output` gives you the instance and
  the ready-made commands).
- A port-forward to the app:

  ```bash
  aws ssm start-session --region eu-west-3 --target <instance-id> \
      --document-name AWS-StartPortForwardingSession \
      --parameters '{"portNumber":["5000"],"localPortNumber":["5000"]}'
  ```

  The scenario defaults to `http://localhost:5000/inject` (override with
  `--endpoint`).

## How to Run

```bash
./scenarios/ecs-ec2-cloud-access/detonate.sh
./scenarios/ecs-ec2-cloud-access/detonate.sh --endpoint http://localhost:15000
./scenarios/ecs-ec2-cloud-access/detonate.sh --wait    # step-by-step
./scenarios/ecs-ec2-cloud-access/detonate.sh --skip-miner  # credentials + EC2 pivot only
```

The script drives every command through `POST /inject` (with retry — the app
drops request bodies on rapid back-to-back calls) and prints the stolen access
key IDs as it goes.

## Attack Flow

1. **RCE sanity checks** — `hostname` / `id` / a deliberately failing command.
   (`whoami` is deliberately avoided, see *Severity tuning*.)
2. **Malware deployment** — download `malware.x64` + the `LD_PRELOAD` library,
   launch the miner with `POOL_URL=stratum+tcp://…` in its environment, plant
   persistence (`authorized_keys` + `/etc/rc.common`).
3. **Mining-pool DNS** — `dig` lookups against a CRYPTOMINER_DOMAIN.
4. **Credential theft #1 (IMDS)** — the stock
   `assets/cloud-access/retrieve-creds-via-imds.sh`, instance profile credentials,
   classic IMDS signals.
5. **Credential theft #2 (ECS credential endpoint)** — curl
   `169.254.170.2${AWS_CONTAINER_CREDENTIALS_RELATIVE_URI}`, stage the **task-role**
   credentials in `/tmp/.aws-cloud-access-creds`.
6. **Lateral movement** — the stock `assets/cloud-access/run-instances-with-creds.sh`:
   `ec2 run-instances` (m5.xlarge, invalid AMI) in 8 regions, all failing, all
   generating CloudTrail events.
7. **Account manipulation** — `chpasswd` backdoor attempt (PAM rejects it; the
   tool execution is what trips the detection).
8. **Cleanup** — kill the miner, remove every artifact, revert the persistence.

## Detection & Correlation

### CloudTrail side — the task ID is everywhere

| Field | Value |
|---|---|
| `userIdentity.arn` | `…assumed-role/<cluster>-app-task-role/<TASK_ID>` |
| `userIdentity.principalId` | `<role-id>:<TASK_ID>` |
| `sts:AssumeRole` minting event | `requestParameters.roleSessionName` = **bare task ID**, `responseElements.credentials.accessKeyId` = the stolen key |
| `userIdentity.inScopeOf` | `issuerType: AWS::ECS::Task`, `credentialsIssuedTo: arn:aws:ecs:…:task/<cluster>/<TASK_ID>` |
| `userAgent` | `… exec-env/AWS_ECS_EC2 … md/command#ec2.run-instances` |

Join key for investigations: **task ID** (stable, links CWS + CloudTrail);
keep the **access key ID** as the taint marker for containment (see
`AssumeRole` minting event for the credentials' expiry window).

Verify with:

```bash
aws cloudtrail lookup-events --region us-east-1 \
    --lookup-attributes AttributeKey=AccessKeyId,AttributeValue=<stolen-key-id>
```

### Runtime side — Workload Protection

Expected signal from the full chain: **"Cryptomining attack chain detected"
(`cryptomining_full_attack_chain`) → `persistent_cryptomining` (HIGH)** —
`miner_execution` + `pool_connection` + `persistence_setup` grouped under the
container-wide `cgroup_*` correlation key.

The bare `/inject` variant (IMDS + `whoami` + IP-check + `ssh`) exercises the
**"Lateral movement attack chain"** rule instead (`credential_based_lateral_movement`
medium up to `comprehensive_lateral_movement` critical).

## Severity tuning (how to stay at HIGH)

The correlation rules escalate to critical when more query families hit within
the evaluation window. To cap a detonation at **high**, leave out the inputs of
the critical cases:

| Leave out | Kills | Prevents |
|---|---|---|
| `ssh` (don't install openssh-client) | `remote_access_tools` | the whole lateral-movement rule, incl. `comprehensive_lateral_movement` (critical) |
| `whoami` | `system_enumeration` | (backup for the above) |
| IP-check domains (checkip.amazonaws.com, …) | `network_reconnaissance` | (backup) |
| `drop_caches` / MSR writes | `system_optimization` | `advanced_cryptomining_operation` (critical) |

Conversely, `ssh` + `whoami` + an IP-check + IMDS in one keyed chain is exactly
how you force the critical lateral-movement case.

## Findings & gotchas from reproducing this

1. **CWS-7353 — systemd re-exec breaks the agent's process lineage.** Ubuntu's
   `apt-daily-upgrade` re-executes systemd (upgrading it) during unattended
   upgrades; afterwards every process started on the host has broken lineage and
   the rule engine ignores its exec/fork/cgroup events — so **no correlation key
   is ever stamped**, while DNS and IMDS rules (which skip the lineage check)
   keep firing. Reproduce/confirm with:

   ```bash
   journalctl --since "<date> 06:00" --until "<date> 06:15" -o short-iso | \
       grep -E "Reexecuting|apt-daily-upgrade|unattended"
   ```

   Mitigations: restart the `datadog-agent` task (daemon service —
   `aws ecs update-service --force-new-deployment`) to rebuild the process tree,
   and disable the apt timers (done in the ECS user-data). See CWS-7353.
2. **The gunicorn worker occasionally wedges at boot** (master listens, worker
   never serves). Bounce the task: `aws ecs update-service --force-new-deployment`.
3. **Workload Protection enforcement kills the fake miner at exec** (exit 137,
   and the kill takes the parent shell down with it, so the `/inject` call
   returns nothing). The exec event still fires `cryptominer_envs`, and the
   `dig` backstop covers the mining-pool DNS. The kill is itself proof the exec
   events reach the rule engine post-CWS-7353.
4. **Port 5000 is not in `accept_incoming_http`'s allowlist**
   (`[80, 443, 3000, 8080, 8000, 8443]`), so the app never registers as a
   public interpreter and `service_shell_*` keys are never stamped via the app
   itself. The container-wide `cgroup_*` key comes from the container-init exec.
5. **`cryptominer_args` is staged** (not shipped by default). To make
   `miner_execution` fire, launch the miner with an environment variable from
   `cryptominer_envs`'s list (`POOL_USER`, `POOL_URL`, `POOL_PASS`,
   `DONATE_LEVEL`) — hence the `POOL_URL=` prefix.
6. **`/inject` drops request bodies** under rapid back-to-back calls. Retry on
   non-200 and re-verify state (the detonate script does this for you).

## Related scenarios

- [`scenarios/cloud-access`](../cloud-access/) — IMDS-only variant, in-cluster
- [`scenarios/langflow-rce`](../langflow-rce/) — same downstream payloads through a real CVE
- [`scenarios/rce-malware`](../rce-malware/) — the miner payload, in-cluster
