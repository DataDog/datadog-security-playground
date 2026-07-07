# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0

provider "aws" {
  region = var.region
}

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  token                  = data.aws_eks_cluster_auth.cluster.token
}

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
    token                  = data.aws_eks_cluster_auth.cluster.token
  }
}

data "aws_eks_cluster_auth" "cluster" {
  name = module.eks.cluster_name
}

# Filter out local zones, which are not currently supported
# with managed node groups
data "aws_availability_zones" "available" {
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

# Canonical's EKS-optimized Ubuntu Noble AMI, tracked dynamically since it's a
# custom AMI (not one of the module's built-in ami_type values) and we want
# security updates as Canonical rolls new builds rather than a hand-pinned ID.
# See the ami_type comment on eks_managed_node_group_defaults below for why
# we're not using AL2023/Bottlerocket here.
data "aws_ssm_parameter" "ubuntu_eks_ami" {
  name = "/aws/service/canonical/ubuntu/eks/24.04/1.35/stable/current/amd64/hvm/ebs-gp3/ami-id"
}

locals {
  cluster_name = "security-playground-${random_string.suffix.result}"
}

resource "random_string" "suffix" {
  length  = 8
  special = false
}

data "aws_iam_policy_document" "assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }

    actions = [
      "sts:AssumeRole",
      "sts:TagSession"
    ]
  }
}

resource "aws_iam_role" "playground" {
  # Suffix with the cluster-suffix random string so multiple clusters can
  # coexist in the same AWS account — IAM role names are globally unique
  # per account, and the prior bare "eks-pod-identity-playground" would
  # collide with any sibling deployment.
  name               = "eks-pod-identity-playground-${random_string.suffix.result}"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
}

resource "aws_eks_pod_identity_association" "association" {
  cluster_name = local.cluster_name
  namespace = var.playground_namespace
  service_account = var.service_account_name
  role_arn = aws_iam_role.playground.arn
}


module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.8.1"

  name = "datadog-security-playground-vpc"

  cidr = "10.0.0.0/16"
  azs  = slice(data.aws_availability_zones.available.names, 0, 3)

  private_subnets = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnets  = ["10.0.4.0/24", "10.0.5.0/24", "10.0.6.0/24"]

  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true

  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
  }
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "20.37.2"

  cluster_name    = local.cluster_name
  cluster_version = "1.35"

  # Required by the org SCP: eks:CreateCluster is denied unless supportType is
  # explicitly set to STANDARD (extended support is blocked account-wide).
  cluster_upgrade_policy = {
    support_type = "STANDARD"
  }

  cluster_endpoint_public_access           = true
  enable_cluster_creator_admin_permissions = true

  # Enable audit logs only
  cluster_enabled_log_types              = ["audit"]
  cloudwatch_log_group_retention_in_days = 7

  cluster_addons = {
    eks-pod-identity-agent = {
      most_recent = true
    }
  }

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  node_security_group_additional_rules = {
    ingress_cluster_api_to_webhook = {
      description                   = "Cluster API to Datadog admission controller webhook"
      protocol                      = "tcp"
      from_port                     = 8000
      to_port                       = 8000
      type                          = "ingress"
      source_cluster_security_group = true
    }
  }

  eks_managed_node_group_defaults = {
    # CWS's memfd/attach_recursive_mnt kprobes were failing to attach on this
    # cluster's original AL2023 nodes (kernel 6.12.73), matching a known break
    # documented in DataDog/datadog-security-playground#131 (1fce7d8): on
    # kernel 7.x, GCC's ISRA optimization compiles attach_recursive_mnt as
    # attach_recursive_mnt.isra.0, a name kprobes can't attach to by the plain
    # symbol. AL2023/Bottlerocket have no k8s-1.35 release below kernel 6.12,
    # so there's no AWS-native AMI type available in the pre-7.x range either
    # way. Ubuntu Noble's EKS-optimized AMI (tracked as "current" here) came up
    # on kernel 6.17 — still 6.x, so it doesn't hit the ISRA rename, and
    # correlation was confirmed working on it. Its bootstrap script is the
    # same classic /etc/eks/bootstrap.sh as AL2, which is what the module's
    # default (non-al2023/bottlerocket) platform renders.
    ami_type = "CUSTOM"
    ami_id   = data.aws_ssm_parameter.ubuntu_eks_ami.value

    enable_bootstrap_user_data = true

    # IMDS hop limit 2 lets pods running on the node reach the node's IMDS at
    # 169.254.169.254 (default in `terraform-aws-modules/eks/aws` v20.x is
    # already 2, but pinning it here makes the requirement explicit and
    # survives module upgrades). Required by the shi-cloud-access-rce-malware scenario so
    # the appsec-test-api pod can retrieve the worker-node-role credentials
    # via IMDS and exercise the AWS API path that produces CloudTrail events.
    metadata_options = {
      http_endpoint               = "enabled"
      http_tokens                 = "required"
      http_put_response_hop_limit = 2
      instance_metadata_tags      = "disabled"
    }
  }

  eks_managed_node_groups = {
    one = {
      name = "node-group-1"

      instance_types = ["t3.medium"]

      min_size     = 1
      max_size     = 2
      desired_size = 1
    }

    two = {
      name = "node-group-2"

      instance_types = ["t3.medium"]

      min_size     = 1
      max_size     = 2
      desired_size = 1
    }
  }
}

