# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0

output "cluster_name" {
  description = "AKS cluster name"
  value       = azurerm_kubernetes_cluster.playground.name
}

output "resource_group_name" {
  description = "Azure resource group containing the cluster"
  value       = azurerm_resource_group.playground.name
}

output "location" {
  description = "Azure region"
  value       = azurerm_resource_group.playground.location
}

output "cluster_endpoint" {
  description = "AKS API server endpoint"
  value       = azurerm_kubernetes_cluster.playground.kube_config[0].host
  sensitive   = true
}

output "get_credentials_command" {
  description = "Command to configure kubectl for this cluster"
  value       = "az aks get-credentials --resource-group ${azurerm_resource_group.playground.name} --name ${azurerm_kubernetes_cluster.playground.name}"
}
