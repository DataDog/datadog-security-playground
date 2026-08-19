# Terraform for a plain EC2 host

Provisions a single Ubuntu 24.04 EC2 instance running the Datadog Agent as a
Docker container with
[Workload Protection](https://docs.datadoghq.com/security/workload_protection/setup/agent/docker/)
enabled. No workload is deployed — this is a bare host for ad-hoc runtime
security experiments.

This stack is independent of [`../eks`](../eks) and [`../ecs-ec2`](../ecs-ec2):
separate state, separate `apply`/`destroy`. It reuses the same variable names
(`region`, `datadog_api_key`, `datadog_site`) so switching between them is
predictable.

## Access model

There are **no inbound security group rules and no SSH key pair**. Access is
over AWS Systems Manager, which only needs outbound connectivity:

```bash
eval "$(terraform output -raw ssm_session_command)"
```

## Prerequisites

- AWS credentials configured, in an account/region that has a **default VPC**
  (this stack uses it deliberately, to avoid a ~$32/month NAT gateway)
- Terraform >= 1.3
- Datadog API key
- The Session Manager plugin for the AWS CLI. It ships separately from the CLI
  itself, and without it every `start-session` call fails with
  `SessionManagerPlugin is not found`:

  ```bash
  brew install --cask session-manager-plugin   # macOS
  session-manager-plugin --version             # verify
  ```

  For Linux and Windows, see the
  [install guide](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html).

## Deployment

```bash
terraform init
terraform apply -var="datadog_api_key=YOUR_API_KEY_HERE" \
    -var="datadog_site=datadoghq.com"
```

Common `datadog_site` values: `datadoghq.com`, `datadoghq.eu`,
`us3.datadoghq.com`, `us5.datadoghq.com`, `ap1.datadoghq.com`, `ddog-gov.com`.

## What gets deployed

- One `t3.medium` Ubuntu 24.04 instance. Ubuntu 24.04 matches the kernel this
  repository already validates CWS against for the local Lima VM.
- Docker, plus the Datadog Agent container started from `user-data.sh.tftpl`
  with `--cgroupns host`, `--pid host`,
  `--security-opt apparmor:unconfined`, the 8 Linux capabilities Workload
  Protection requires, and the documented host volume mounts. No
  `--privileged`. The image defaults to `gcr.io/datadoghq/agent:7.83.0-rc.3`, a
  pinned release candidate, so the playground exercises Workload Protection
  changes before they ship and every apply gets the same Agent. Bump
  `agent_image` for a newer RC, or pass
  `-var="agent_image=registry.datadoghq.com/agent:7"` for the stable Agent.
- `DD_API_KEY` in an SSM Parameter Store `SecureString`, fetched at boot by the
  instance role rather than inlined into user-data (which is readable through
  `ec2:DescribeInstanceAttribute` and from IMDS)
- Egress-only security group; instance role scoped to SSM plus reading that one
  parameter

## Verifying the deployment

The agent is installed at boot, so give the instance a couple of minutes. First
confirm it registered with SSM, which is also what makes it reachable:

```bash
aws ssm describe-instance-information \
    --region "$(terraform output -raw region)" \
    --filters "Key=InstanceIds,Values=$(terraform output -raw instance_id)" \
    --query 'InstanceInformationList[0].{status:PingStatus,platform:PlatformName}'
```

Then check the agent itself:

```bash
eval "$(terraform output -raw ssm_session_command)"

sudo docker ps
sudo docker logs dd-agent
sudo docker exec dd-agent agent status
sudo docker exec dd-agent security-agent status
```

A healthy container is not proof that Workload Protection attached to the
kernel — `security-agent status` is what confirms it. Look for the Runtime
Security section; if it reports that it cannot reach
`/opt/datadog-agent/run/runtime-security.sock`, `system-probe` did not start.

The bootstrap log is at `/var/log/cloud-init-output.log`.

`terraform output` lists every command this stack generates.

## Loading a CWS policy

`./load-policy.sh` applies a local policy file to the running agent:

```bash
./load-policy.sh my-rules.policy
```

It base64-encodes the file, sends it as a parameter to the
`*-load-cws-policy` SSM document, and prints the result. On the host the
document sets the agent log level to `debug` (policy errors are only visible
there), copies the file into `/etc/datadog-agent/runtime-security.d/`, then runs
`system-probe runtime policy check`, `system-probe runtime policy reload`, and
`security-agent status`.

Note that the agent only loads files whose name ends in `.policy`; both the
script and the document reject anything else rather than silently doing nothing.
The document runs under `set -euo pipefail`, so a policy that fails `check`
reports a failed command instead of a success with a rejected policy.

Why a document instead of `docker cp` from your laptop: Run Command sends
commands, not files, and this keeps the SSM-only access model — no inbound port,
no SSH, and every load is recorded in CloudTrail as a `SendCommand` event.

The policy travels inline, so the ceiling is the 64 KB SSM document size limit,
which a base64-encoded file inflates by about a third. That is ample for
hand-written policies; a much larger one would need staging through S3 instead.

## Cost

One `t3.medium` is roughly **$0.05/hour** (~$34/month if left running). SSM and
the default VPC are free. **Run `terraform destroy` when you are done.**

```bash
terraform destroy -var="datadog_api_key=YOUR_API_KEY_HERE"
```

## File structure

- `main.tf`: provider, default VPC lookup, IAM, SSM parameter, AMI, instance
- `user-data.sh.tftpl`: boot script that installs Docker and starts the agent
- `policy.tf`: SSM document that loads a CWS policy file
- `load-policy.sh`: wrapper that sends a local policy file to that document
- `variables.tf`: input variables
- `outputs.tf`: output values, including the SSM session command
- `terraform.tf`: Terraform and provider version constraints

## Troubleshooting

**`SessionManagerPlugin is not found`**: the Session Manager plugin is missing.
See Prerequisites above — it is a separate install from the AWS CLI.

**`start-session` fails otherwise**: the instance needs a few minutes to
register with SSM after boot. Confirm with `aws ssm describe-instance-information`.

**No Workload Protection signals**: read
`/var/log/cloud-init-output.log` to confirm the bootstrap ran to completion —
it runs under `set -e`, so a single failed step leaves the host with no agent at
all. Then check `sudo docker logs dd-agent` and
`sudo docker exec dd-agent security-agent status`. Workload Protection requires
Agent 7.46 or later.

**No default VPC in this region**: this stack will fail to plan. Either pick a
region that has one, or create one with
`aws ec2 create-default-vpc --region <region>`.
