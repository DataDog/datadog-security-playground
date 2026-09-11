# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0

variable "region" {
  description = "AWS region"
  type        = string
  default     = "eu-west-3"
}

variable "playground_namespace" {
  description = "Namespace for the playground apps"
  type        = string
  default     = "playground"
}

variable "datadog_namespace" {
  description = "Namespace for the Datadog agent"
  type        = string
  default     = "datadog"
}

variable "service_account_name" {
  description = "Service account name"
  type        = string
  default     = "playground-sa"
}

variable "pod_identity_role_name" {
  description = "Name of the IAM role used by the EKS pod identity association"
  type        = string
  default     = "eks-pod-identity-playground"
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

variable "datadog_app_key" {
  description = "Datadog application key used to manage Datadog resources (CSM Threats agent rules). Needs the security_monitoring_cws_agent_rules_write permission. https://app.datadoghq.com/organization-settings/application-keys"
  type        = string
  sensitive   = true
}

variable "csm_default_policy_name" {
  description = "Name of the CSM Threats (Workload Protection) policy the agent rules are attached to. The helm-deployed agent uses the org default."
  type        = string
  default     = "Default Policy"
} 