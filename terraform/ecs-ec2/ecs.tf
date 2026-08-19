# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0

# ECS workloads: the Datadog Agent with Workload Protection, and the playground app.
#
# The agent container definition follows
# https://docs.datadoghq.com/security/workload_protection/setup/agent/ecs_ec2/
# Elevated access is granted through the capability list below rather than
# through `privileged`.

locals {
  # Fixed, not a variable: app/Dockerfile hardcodes `gunicorn -b :5000`, and
  # scripts/tool.sh defaults to http://localhost:5000.
  app_port = 5000

  # Host paths the runtime security agent and system-probe need. Kept as a
  # single list so the volume blocks and mount points cannot drift apart.
  agent_volumes = [
    { name = "docker_sock", host_path = "/var/run/docker.sock", container_path = "/var/run/docker.sock", read_only = true },
    { name = "proc", host_path = "/proc/", container_path = "/host/proc/", read_only = true },
    { name = "cgroup", host_path = "/sys/fs/cgroup/", container_path = "/host/sys/fs/cgroup", read_only = true },
    { name = "passwd", host_path = "/etc/passwd", container_path = "/etc/passwd", read_only = true },
    { name = "os_release", host_path = "/etc/os-release", container_path = "/host/etc/os-release", read_only = true },
    { name = "root", host_path = "/", container_path = "/host/root", read_only = true },
    # system-probe attaches eBPF programs through debugfs, which must be writable.
    { name = "kernel_debug", host_path = "/sys/kernel/debug", container_path = "/sys/kernel/debug", read_only = false },
  ]

  agent_capabilities = [
    "SYS_ADMIN",
    "SYS_RESOURCE",
    "SYS_PTRACE",
    "NET_ADMIN",
    "NET_BROADCAST",
    "NET_RAW",
    "IPC_LOCK",
    "CHOWN",
  ]

  agent_environment = {
    DD_SITE = var.datadog_site

    # Workload Protection: runtime security (CWS) and system-probe.
    DD_RUNTIME_SECURITY_CONFIG_ENABLED                      = "true"
    DD_SYSTEM_PROBE_ENABLED                                 = "true"
    DD_RUNTIME_SECURITY_CONFIG_REMOTE_CONFIGURATION_ENABLED = "true"

    # CSPM and host benchmarks.
    DD_COMPLIANCE_CONFIG_ENABLED                 = "true"
    DD_COMPLIANCE_CONFIG_HOST_BENCHMARKS_ENABLED = "true"

    # SBOM / container image collection, mirroring the EKS values file.
    DD_SBOM_ENABLED                 = "true"
    DD_SBOM_CONTAINER_IMAGE_ENABLED = "true"
    DD_SBOM_HOST_ENABLED            = "true"
    DD_CONTAINER_IMAGE_ENABLED      = "true"

    # Accept traces from the app container, which runs in a separate task.
    DD_APM_ENABLED           = "true"
    DD_APM_NON_LOCAL_TRAFFIC = "true"
  }
}

resource "aws_ecs_task_definition" "datadog_agent" {
  family                   = "${local.cluster_name}-datadog-agent"
  requires_compatibilities = ["EC2"]
  network_mode             = "bridge"
  execution_role_arn       = aws_iam_role.task_execution.arn

  dynamic "volume" {
    for_each = local.agent_volumes
    content {
      name      = volume.value.name
      host_path = volume.value.host_path
    }
  }

  container_definitions = jsonencode([
    {
      name      = "datadog-agent"
      image     = local.agent_image
      essential = true

      # The docs call out raising this if SBOM extraction from container images fails.
      memory = 768

      environment = [
        for name, value in local.agent_environment : {
          name  = name
          value = value
        }
      ]

      secrets = [
        {
          name      = "DD_API_KEY"
          valueFrom = aws_ssm_parameter.datadog_api_key.arn
        }
      ]

      portMappings = [
        {
          containerPort = 8126
          hostPort      = 8126
          protocol      = "tcp"
        }
      ]

      mountPoints = [
        for volume in local.agent_volumes : {
          sourceVolume  = volume.name
          containerPath = volume.container_path
          readOnly      = volume.read_only
        }
      ]

      linuxParameters = {
        capabilities = {
          add = local.agent_capabilities
        }
      }
    }
  ])
}

# One agent per container instance.
resource "aws_ecs_service" "datadog_agent" {
  name                = "datadog-agent"
  cluster             = aws_ecs_cluster.main.id
  task_definition     = aws_ecs_task_definition.datadog_agent.arn
  scheduling_strategy = "DAEMON"

  depends_on = [aws_instance.ecs]
}

################################################################################
# Playground application
################################################################################

resource "aws_ecs_task_definition" "app" {
  family                   = "${local.cluster_name}-app"
  requires_compatibilities = ["EC2"]
  network_mode             = "bridge"
  execution_role_arn       = aws_iam_role.task_execution.arn
  task_role_arn            = aws_iam_role.app_task.arn

  container_definitions = jsonencode([
    {
      name      = "playground-app"
      image     = var.app_image
      essential = true
      cpu       = 512
      memory    = 1024

      # 5000 is fixed by the image: app/Dockerfile starts gunicorn with `-b :5000`
      # and offers no way to override it. Bound to the same host port so it is
      # reachable over SSM port forwarding. The security group has no ingress
      # rules, so this is not internet-facing.
      portMappings = [
        {
          containerPort = local.app_port
          hostPort      = local.app_port
          protocol      = "tcp"
        }
      ]

      environment = [
        { name = "DD_SERVICE", value = "playground-app" },
        { name = "DD_ENV", value = "playground-env" },
        { name = "DD_APPSEC_ENABLED", value = "true" },
        { name = "DD_IAST_ENABLED", value = "true" },
        { name = "DD_APPSEC_SCA_ENABLED", value = "true" },
        # In bridge mode the agent's mapped port is reachable on the Docker
        # bridge gateway. The EKS manifest uses status.hostIP for the same purpose.
        { name = "DD_AGENT_HOST", value = "172.17.0.1" },
        { name = "DD_TRACE_AGENT_PORT", value = "8126" },
      ]
    }
  ])
}

resource "aws_ecs_service" "app" {
  name            = "playground-app"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.app.arn
  desired_count   = 1

  # Enables `aws ecs execute-command`. Note that AWS only supports ECS Exec on
  # ECS-optimized AMIs, and this stack runs stock Ubuntu, so it may not come up.
  # It is left on because it costs nothing if unsupported, and because the
  # reliable fallback needs no extra infrastructure: open an SSM session on the
  # host and use `docker exec`. See the README.
  enable_execute_command = true

  depends_on = [aws_instance.ecs]
}
