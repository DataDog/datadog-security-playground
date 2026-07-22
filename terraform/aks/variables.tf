# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0

variable "location" {
  description = "Azure region (e.g. westeurope, eastus)"
  type        = string
  default     = "westeurope"
}

variable "resource_group_name" {
  description = "Name of the Azure resource group"
  type        = string
  default     = "datadog-security-playground"
}

variable "cluster_name" {
  description = "Name of the AKS cluster"
  type        = string
  default     = "security-playground"
}

variable "node_count" {
  description = "Number of nodes per node pool"
  type        = number
  default     = 1
}

variable "vm_size" {
  description = "VM size for AKS nodes"
  type        = string
  default     = "Standard_D2s_v3"
}

variable "kubernetes_version" {
  description = "Kubernetes version for the AKS cluster"
  type        = string
  default     = "1.34"
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

variable "datadog_cluster_name" {
  description = "Cluster name tag reported to Datadog (overrides DD_CLUSTER_NAME in datadog-agent.yaml)"
  type        = string
  default     = "playground-cluster-aks"
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
