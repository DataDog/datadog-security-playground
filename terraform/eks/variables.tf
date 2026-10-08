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
  description = "Datadog application key used to manage the Datadog resources (permissions listed in the README)"
  type        = string
  sensitive   = true
}

variable "tags" {
  description = "Tags added to every AWS resource Terraform creates"
  type        = map(string)
  default     = {}
}

variable "cluster_endpoint_public_access_cidrs" {
  description = "CIDR blocks allowed to reach the public EKS API endpoint"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "access_entries" {
  description = "Extra EKS access entries, in the terraform-aws-modules/eks access_entries format, for example to give another IAM principal access to the cluster"
  type        = any
  default     = {}
}

variable "exclude_zone_ids" {
  description = "Availability zone IDs never used for the cluster, for example use1-az3, which EKS doesn't support"
  type        = list(string)
  default     = []
}

variable "datadog_helm_chart_version" {
  description = "Version of the datadog Helm chart; null installs the latest"
  type        = string
  default     = null
}

variable "extra_agent_values" {
  description = "Helm values (YAML strings) applied after deploy/datadog-agent.yaml, for example to pin the agent image"
  type        = list(string)
  default     = []
}

variable "playground_image" {
  description = "Image of the playground-app container; null keeps the image set in deploy/app.yaml"
  type        = string
  default     = null
}

variable "langflow_image" {
  description = "Image of the langflow-vulnerable container; null keeps the image set in deploy/langflow-vulnerable.yaml"
  type        = string
  default     = null
}

variable "langflow_service" {
  description = "Service exposing langflow-vulnerable on port 7860; null creates none"
  type = object({
    type          = optional(string, "ClusterIP")
    source_ranges = optional(list(string), [])
    annotations   = optional(map(string), {})
  })
  default = null

  validation {
    condition     = var.langflow_service == null ? true : contains(["ClusterIP", "NodePort", "LoadBalancer"], var.langflow_service.type)
    error_message = "langflow_service.type must be ClusterIP, NodePort, or LoadBalancer."
  }

  validation {
    condition = var.langflow_service == null ? true : (
      var.langflow_service.type != "LoadBalancer" || (
        length(var.langflow_service.source_ranges) > 0 &&
        alltrue([for r in var.langflow_service.source_ranges : try(tonumber(regex("^[0-9.]+/([0-9]+)$", r)[0]) >= 16, false)])
      )
    )
    error_message = "A LoadBalancer langflow_service needs source_ranges, each an IPv4 CIDR block no broader than /16: langflow-vulnerable is exploitable (CVE-2025-3248)."
  }
}
