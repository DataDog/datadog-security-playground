# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0

provider "aws" {
  region = var.region
}

locals {
  cluster_name = "security-playground-${random_string.suffix.result}"

  # Split so swapping agent versions is a one-word override, while still
  # allowing another registry.
  agent_image = "${var.agent_image_repo}:${var.agent_image_tag}"
}

resource "random_string" "suffix" {
  length  = 8
  special = false
  upper   = false
}

# Use the account's default VPC. The playground needs outbound reachability only
# (SSM, Datadog intake, image pulls), so a dedicated VPC with a NAT gateway would
# add cost without adding realism.
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }

  # Restrict to the subnets AWS created with the default VPC. Accounts often
  # have extra private subnets added to it, and those have no internet gateway
  # route, so a public IP alone would not give the instance connectivity.
  filter {
    name   = "default-for-az"
    values = ["true"]
  }
}

# Egress only. There are deliberately no ingress rules: the vulnerable app is
# reached through SSM port forwarding, not from the internet.
resource "aws_security_group" "instance" {
  name        = "${local.cluster_name}-instance"
  description = "Egress-only access for the security playground ECS container instance"
  vpc_id      = data.aws_vpc.default.id

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Store the Datadog API key as a SecureString so it is not readable through
# ecs:DescribeTaskDefinition.
resource "aws_ssm_parameter" "datadog_api_key" {
  name        = "/${local.cluster_name}/datadog-api-key"
  description = "Datadog API key for the security playground ECS agent"
  type        = "SecureString"
  value       = var.datadog_api_key
}

################################################################################
# IAM
################################################################################

data "aws_iam_policy_document" "ec2_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "ecs_tasks_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

# Role for the container instance: register with ECS, and be reachable over SSM
# so no SSH key pair or inbound port is needed.
resource "aws_iam_role" "instance" {
  name               = "${local.cluster_name}-instance"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json
}

resource "aws_iam_role_policy_attachment" "instance_ecs" {
  role       = aws_iam_role.instance.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}

resource "aws_iam_role_policy_attachment" "instance_ssm" {
  role       = aws_iam_role.instance.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "instance" {
  name = "${local.cluster_name}-instance"
  role = aws_iam_role.instance.name
}

# Execution role: pulls images and resolves the DD_API_KEY secret.
resource "aws_iam_role" "task_execution" {
  name               = "${local.cluster_name}-task-execution"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume_role.json
}

resource "aws_iam_role_policy_attachment" "task_execution" {
  role       = aws_iam_role.task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

data "aws_iam_policy_document" "read_api_key" {
  statement {
    effect    = "Allow"
    actions   = ["ssm:GetParameters"]
    resources = [aws_ssm_parameter.datadog_api_key.arn]
  }
}

resource "aws_iam_role_policy" "task_execution_read_api_key" {
  name   = "read-datadog-api-key"
  role   = aws_iam_role.task_execution.id
  policy = data.aws_iam_policy_document.read_api_key.json
}

# Task role for the app, scoped to what ECS Exec needs so `aws ecs
# execute-command` works as the equivalent of `kubectl exec`.
resource "aws_iam_role" "app_task" {
  name               = "${local.cluster_name}-app-task"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume_role.json
}

data "aws_iam_policy_document" "ecs_exec" {
  statement {
    effect = "Allow"
    actions = [
      "ssmmessages:CreateControlChannel",
      "ssmmessages:CreateDataChannel",
      "ssmmessages:OpenControlChannel",
      "ssmmessages:OpenDataChannel",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "app_task_ecs_exec" {
  name   = "ecs-exec"
  role   = aws_iam_role.app_task.id
  policy = data.aws_iam_policy_document.ecs_exec.json
}

################################################################################
# Cluster and container instance
################################################################################

resource "aws_ecs_cluster" "main" {
  name = local.cluster_name

  configuration {
    execute_command_configuration {
      logging = "DEFAULT"
    }
  }
}

# Ubuntu 24.04, matching ../ec2 and the local Lima VM, so Workload Protection
# runs against one kernel across every stack in this repository.
#
# AWS publishes no ECS-optimized Ubuntu AMI (the Linux variants are Amazon Linux
# and Bottlerocket only), so this is a stock Canonical image and user-data
# installs Docker and the ECS agent. See user-data.sh.tftpl.
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# A single instance, no Auto Scaling group. This is a lab, not a fleet.
resource "aws_instance" "ecs" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type
  subnet_id                   = data.aws_subnets.default.ids[0]
  vpc_security_group_ids      = [aws_security_group.instance.id]
  iam_instance_profile        = aws_iam_instance_profile.instance.name
  associate_public_ip_address = true

  user_data = templatefile("${path.module}/user-data.sh.tftpl", {
    region       = var.region
    cluster_name = local.cluster_name
  })

  # Re-provision if the bootstrap script or its inputs change.
  user_data_replace_on_change = true

  tags = {
    Name = "${local.cluster_name}-instance"
  }
}
