# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0

provider "aws" {
  region = var.region
}

locals {
  name = "security-playground-ec2-${random_string.suffix.result}"

  # Shared by the bootstrap script and the policy-loading SSM document, so the
  # two cannot drift apart.
  agent_container = "dd-agent"
}

resource "random_string" "suffix" {
  length  = 8
  special = false
  upper   = false
}

# Use the account's default VPC. The host needs outbound reachability only
# (SSM, Datadog intake, image pulls), so a dedicated VPC with a NAT gateway
# would add cost without adding realism.
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
  # route, so a public IP alone would not give the instance connectivity for
  # apt-get, the image pull, SSM registration, or Datadog intake.
  filter {
    name   = "default-for-az"
    values = ["true"]
  }
}

# Egress only. There are deliberately no ingress rules: the host is reached
# through SSM, not SSH.
resource "aws_security_group" "instance" {
  name        = "${local.name}-instance"
  description = "Egress-only access for the security playground EC2 host"
  vpc_id      = data.aws_vpc.default.id

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Store the Datadog API key as a SecureString rather than inlining it into
# user-data, which is readable through ec2:DescribeInstanceAttribute and from
# IMDS on the instance itself.
resource "aws_ssm_parameter" "datadog_api_key" {
  name        = "/${local.name}/datadog-api-key"
  description = "Datadog API key for the security playground EC2 agent"
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

resource "aws_iam_role" "instance" {
  name               = "${local.name}-instance"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json
}

# Makes the host reachable over SSM, so no SSH key pair or inbound port is needed.
resource "aws_iam_role_policy_attachment" "instance_ssm" {
  role       = aws_iam_role.instance.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

data "aws_iam_policy_document" "read_api_key" {
  statement {
    effect    = "Allow"
    actions   = ["ssm:GetParameter"]
    resources = [aws_ssm_parameter.datadog_api_key.arn]
  }
}

resource "aws_iam_role_policy" "instance_read_api_key" {
  name   = "read-datadog-api-key"
  role   = aws_iam_role.instance.id
  policy = data.aws_iam_policy_document.read_api_key.json
}

resource "aws_iam_instance_profile" "instance" {
  name = "${local.name}-instance"
  role = aws_iam_role.instance.name
}

################################################################################
# Instance
################################################################################

# Ubuntu 24.04. The repository already validates CWS against this kernel for the
# local Lima VM, so it is the known-good choice here too.
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

resource "aws_instance" "playground" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type
  subnet_id                   = data.aws_subnets.default.ids[0]
  vpc_security_group_ids      = [aws_security_group.instance.id]
  iam_instance_profile        = aws_iam_instance_profile.instance.name
  associate_public_ip_address = true

  user_data = templatefile("${path.module}/user-data.sh.tftpl", {
    region          = var.region
    api_key_path    = aws_ssm_parameter.datadog_api_key.name
    datadog_site    = var.datadog_site
    agent_image     = var.agent_image
    agent_container = local.agent_container
  })

  # Re-provision if the bootstrap script or its inputs change.
  user_data_replace_on_change = true

  tags = {
    Name = local.name
  }
}
