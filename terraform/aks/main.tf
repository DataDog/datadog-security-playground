# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0

provider "azurerm" {
  features {}
}

provider "kubernetes" {
  host                   = azurerm_kubernetes_cluster.playground.kube_config[0].host
  client_certificate     = base64decode(azurerm_kubernetes_cluster.playground.kube_config[0].client_certificate)
  client_key             = base64decode(azurerm_kubernetes_cluster.playground.kube_config[0].client_key)
  cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.playground.kube_config[0].cluster_ca_certificate)
}

provider "helm" {
  kubernetes {
    host                   = azurerm_kubernetes_cluster.playground.kube_config[0].host
    client_certificate     = base64decode(azurerm_kubernetes_cluster.playground.kube_config[0].client_certificate)
    client_key             = base64decode(azurerm_kubernetes_cluster.playground.kube_config[0].client_key)
    cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.playground.kube_config[0].cluster_ca_certificate)
  }
}

resource "azurerm_resource_group" "playground" {
  name     = var.resource_group_name
  location = var.location
}

resource "azurerm_virtual_network" "playground" {
  name                = "playground-vnet"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.playground.location
  resource_group_name = azurerm_resource_group.playground.name
}

resource "azurerm_subnet" "aks" {
  name                 = "aks-subnet"
  resource_group_name  = azurerm_resource_group.playground.name
  virtual_network_name = azurerm_virtual_network.playground.name
  address_prefixes     = ["10.0.1.0/24"]
}

# User-assigned managed identity for the playground workload (cloud-access scenario)
resource "azurerm_user_assigned_identity" "playground" {
  name                = "playground-workload-identity"
  location            = azurerm_resource_group.playground.location
  resource_group_name = azurerm_resource_group.playground.name
}

# Federated credential linking the K8s service account to the managed identity
resource "azurerm_federated_identity_credential" "playground" {
  name                = "playground-federated-credential"
  resource_group_name = azurerm_resource_group.playground.name
  parent_id           = azurerm_user_assigned_identity.playground.id
  audience            = ["api://AzureADTokenExchange"]
  issuer              = azurerm_kubernetes_cluster.playground.oidc_issuer_url
  subject             = "system:serviceaccount:${var.playground_namespace}:${var.service_account_name}"
}

resource "azurerm_kubernetes_cluster" "playground" {
  name                = var.cluster_name
  location            = azurerm_resource_group.playground.location
  resource_group_name = azurerm_resource_group.playground.name
  dns_prefix          = var.cluster_name
  kubernetes_version  = var.kubernetes_version

  # Enable OIDC issuer and Workload Identity (Azure equivalent of EKS Pod Identity)
  oidc_issuer_enabled       = true
  workload_identity_enabled = true

  default_node_pool {
    name           = "system"
    node_count     = var.node_count
    vm_size        = var.vm_size
    vnet_subnet_id = azurerm_subnet.aks.id

    upgrade_settings {
      max_surge = "10%"
    }
  }

  identity {
    type = "SystemAssigned"
  }

  # Enable audit logs to match EKS audit log behaviour
  monitor_metrics {}

  network_profile {
    network_plugin    = "azure"
    load_balancer_sku = "standard"
  }

  tags = {
    project = "datadog-security-playground"
  }
}

# User node pool for playground workloads (mirrors EKS node-group-2)
resource "azurerm_kubernetes_cluster_node_pool" "user" {
  name                  = "user"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.playground.id
  vm_size               = var.vm_size
  node_count            = var.node_count
  vnet_subnet_id        = azurerm_subnet.aks.id

  tags = {
    project = "datadog-security-playground"
  }
}
