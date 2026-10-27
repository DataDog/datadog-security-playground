# Terraform for ECS (EC2 launch type)

Provisions a single-instance ECS cluster running the Datadog Agent with
[Workload Protection](https://docs.datadoghq.com/security/workload_protection/setup/ecs_ec2/)
enabled, plus the security playground application.

This stack is independent of [`../eks`](../eks): separate state, separate
`apply`/`destroy`. It reuses the same variable names (`region`,
`datadog_api_key`, `datadog_site`) so switching between them is predictable.

## Access model

There are **no inbound security group rules and no SSH key pair**. Everything
goes through AWS Systems Manager, which only needs outbound connectivity:

| Need | Command |
|---|---|
| Shell on the host | `aws ssm start-session --target <instance-id>` |
| Reach the app locally | `AWS-StartPortForwardingSession` on port 5000 |
| Shell in the app container | `sudo docker exec` from a host session (see below) |

Port forwarding is the direct analogue of the `kubectl port-forward` flow the
EKS stack uses. Because `scripts/tool.sh` already targets
`http://localhost:5000`, HTTP-based scenarios such as `bpfdoor` and
`rce-malware` can target the app once the tunnel is up. This stack does not
install the separate Langflow application or Kubernetes CWS instrumentation;
scenarios requiring those components need their own deployment. The cloud-access
scenario also depends on the account's IMDS settings and IAM permissions.

## Prerequisites

- AWS credentials configured, in an account/region that has a **default VPC**
  (this stack uses it deliberately, to avoid a NAT gateway)
- Terraform >= 1.3 and < 2.0
- AWS CLI
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

Unlike the EKS stack, this is a **single-stage apply** — there is no Kubernetes
provider that needs the cluster to exist first.

```bash
cd terraform/ecs-ec2
terraform init
export TF_VAR_datadog_api_key="$DD_API_KEY"
export TF_VAR_datadog_site="$DD_SITE"
terraform apply
```

Export `DD_API_KEY` and `DD_SITE` as described in the repository's
[configuration guide](../../README.md#-configuration) first. Terraform stores
the API key in local state even though its input is marked sensitive. Keep
state and plan files private; the repository ignores state files and tfvars.

Common `datadog_site` values: `datadoghq.com`, `datadoghq.eu`,
`us3.datadoghq.com`, `us5.datadoghq.com`, `ap1.datadoghq.com`, `ddog-gov.com`.

## Usage

Open a shell on the container instance:

```bash
eval "$(terraform output -raw ssm_session_command)"
```

Forward the app to `localhost:5000`, then run a scenario from another terminal:

```bash
eval "$(terraform output -raw app_port_forward_command)"

# in a second terminal, from the repository root
./scenarios/bpfdoor/detonate.sh --wait
```

Open a shell in the app container through the SSM-managed host:

```bash
eval "$(terraform output -raw app_exec_command)"
```

ECS Exec is not enabled: this stack uses stock Ubuntu, outside AWS's documented
[ECS Exec support for EC2](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/ecs-exec.html).

`terraform output` lists every command this stack generates.

## Verifying the deployment

The instance installs Docker and the ECS agent at boot, so registration takes a
couple of minutes. Confirm it joined the cluster and both services are running:

```bash
CLUSTER="$(terraform output -raw cluster_name)"
REGION="$(terraform output -raw region)"

aws ecs describe-clusters --region "$REGION" --clusters "$CLUSTER" \
    --query 'clusters[0].{instances:registeredContainerInstancesCount,running:runningTasksCount}'

aws ecs list-tasks --region "$REGION" --cluster "$CLUSTER"
```

`instances` should be `1` and `running` should be `2` (the agent and the app).
If `instances` is `0`, the bootstrap failed — see Troubleshooting below.

Then check the agent itself from a host session:

```bash
eval "$(terraform output -raw ssm_session_command)"

sudo docker info --format 'cgroup driver={{.CgroupDriver}} cgroup version={{.CgroupVersion}}'
findmnt /sys/kernel/debug
sudo docker ps
AGENT="$(sudo docker ps -qf name=datadog-agent)"
sudo docker logs "$AGENT"
sudo docker exec "$AGENT" agent status
sudo docker exec "$AGENT" security-agent status
```

The Docker cgroup driver should be `cgroupfs`, and `findmnt` should show a
read-write `debugfs` mount. After opening the port-forward tunnel, confirm the
app responds with `curl --fail http://localhost:5000/`.

A running task is not proof that Workload Protection attached to the kernel —
`security-agent status` is what confirms it. Look for the Runtime Security
section; if it reports that it cannot reach
`/opt/datadog-agent/run/runtime-security.sock`, `system-probe` did not start.

## What gets deployed

- ECS cluster with one `t3.medium` container instance, no Auto Scaling group
- **Ubuntu 24.04**, matching [`../ec2`](../ec2) and the local Lima VM, so
  Workload Protection uses the same OS release across these environments.
  The AMI lookup selects the latest image, so exact kernel versions may differ. AWS
  publishes no ECS-optimized Ubuntu AMI, so this is a stock Canonical image and
  `user-data.sh.tftpl` installs Docker and registers the host with the cluster
  using the `amazon-ecs-init` package.
- Datadog Agent as a `DAEMON` service, with the 8 Linux capabilities and 7 host
  volume mounts from the ECS Workload Protection setup. Host PID and cgroup
  namespaces and an unconfined AppArmor profile match the Docker setup on Ubuntu;
  the Agent is not privileged. The image
  defaults to `gcr.io/datadoghq/agent:7.83.0-rc.3`, a pinned release candidate,
  so the playground exercises Workload Protection changes before they ship and
  every apply gets the same Agent.

Swapping agents is a one-word override:

```bash
terraform apply -var="agent_image_tag=7"                    # latest stable
terraform apply -var="agent_image_tag=7.84.0-rc.1"          # a newer RC
terraform apply -var="agent_image_repo=1234.dkr.ecr.eu-west-3.amazonaws.com/agent" \
                -var="agent_image_tag=my-dev-build"         # your own build
```
- Playground app service on host port 5000. Updates stop the old app task before
  starting its replacement, so a deployment briefly interrupts the app.
- Encrypted 30 GiB gp3 root volume and bounded Docker log rotation
- `DD_API_KEY` in an SSM Parameter Store `SecureString`, resolved by the task
  execution role — so it is not readable through `ecs:DescribeTaskDefinition`
- Egress-only security group; IAM roles for ECS registration, SSM host access,
  image pulls, and reading the Datadog API key

## Cost

Charges include the EC2 instance, its 30 GiB EBS volume, public IPv4 address,
and data transfer. Rates depend on region and usage; consult
[AWS pricing](https://calculator.aws/) before leaving the lab running.
**Run `terraform destroy` when you are done**, using the same variable overrides
as deployment. Keep `TF_VAR_datadog_api_key` exported until cleanup finishes.

```bash
terraform destroy
```

## File structure

- `main.tf`: provider, default VPC lookup, IAM, SSM parameter, cluster, instance
- `user-data.sh.tftpl`: boot script that installs Docker and the ECS agent
- `ecs.tf`: agent and app task definitions and services
- `variables.tf`: input variables
- `outputs.tf`: output values, including copy-pasteable SSM commands
- `terraform.tf`: Terraform and provider version constraints

## Troubleshooting

**Instance never registers with the cluster**: the ECS agent is installed at
boot, so check `/var/log/cloud-init-output.log` first, then
`/var/log/ecs/ecs-agent.log` and `systemctl status ecs`. The instance must have
outbound 443.

**`amazon-ecs-init` download fails**: the `.deb` is fetched from a per-region
S3 bucket, and not every region publishes one. If your `region` is not in the
[agent install table](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/ecs-agent-install.html),
the download 404s.

**`aws ecs execute-command` fails**: this stack uses SSM host sessions and
`docker exec`. Use the `app_exec_command` output instead.

**`SessionManagerPlugin is not found`**: the Session Manager plugin is missing.
See Prerequisites above — it is a separate install from the AWS CLI.

**`start-session` fails otherwise**: the instance needs a few minutes to
register with SSM after boot. Confirm with
`aws ssm describe-instance-information`.

**No Workload Protection signals**: run the agent checks under Verifying the
deployment above, and confirm `/sys/kernel/debug` mounted read-write. Workload
Protection requires Agent 7.46 or later.

**A service stays at 0 running tasks**: read the stopped task's reason, which
names the failing mount or capability:

```bash
aws ecs describe-tasks --region "$REGION" --cluster "$CLUSTER" \
    --tasks "$(aws ecs list-tasks --region "$REGION" --cluster "$CLUSTER" \
        --desired-status STOPPED --query 'taskArns[0]' --output text)" \
    --query 'tasks[0].{stopped:stoppedReason,containers:containers[].reason}'
```

**No default VPC in this region**: this stack will fail to plan. Either pick a
region that has one, or create one with
`aws ec2 create-default-vpc --region <region>`.
