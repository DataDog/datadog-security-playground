# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0

variable "region" {
  description = "AWS region"
  type        = string
  default     = "eu-west-3"
}

variable "datadog_api_key" {
  description = "Datadog API key for agent authentication"
  type        = string
  sensitive   = true
}

variable "datadog_site" {
  description = "Datadog site (e.g., datadoghq.com, datadoghq.eu, us3.datadoghq.com)"
  type        = string
  default     = "datadoghq.com"
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.medium"
}

variable "agent_image" {
  description = "Datadog Agent image. Defaults to a pinned release candidate, so this playground exercises Workload Protection changes before they ship and every apply gets the same Agent; override with registry.datadoghq.com/agent:7 for the stable Agent. Requires Agent 7.46 or later."
  type        = string
  default     = "gcr.io/datadoghq/agent:7.83.0-rc.3"
}
