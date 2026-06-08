# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0

# Kubernetes resources that depend on the AKS cluster being created first

# Create Kubernetes namespace for the playground
resource "kubernetes_namespace" "playground" {
  metadata {
    name = var.playground_namespace
  }
}

# Create Kubernetes namespace for the Datadog agent
resource "kubernetes_namespace" "datadog" {
  metadata {
    name = var.datadog_namespace
  }
}

# Create Kubernetes service account with Azure Workload Identity annotation
resource "kubernetes_service_account" "playground" {
  metadata {
    name      = var.service_account_name
    namespace = kubernetes_namespace.playground.metadata[0].name
    annotations = {
      "azure.workload.identity/client-id" = azurerm_user_assigned_identity.playground.client_id
    }
    labels = {
      "azure.workload.identity/use" = "true"
    }
  }
}

# Create service account token
resource "kubernetes_secret" "playground_token" {
  depends_on = [kubernetes_service_account.playground]

  metadata {
    name      = "${var.service_account_name}-token"
    namespace = kubernetes_namespace.playground.metadata[0].name
    annotations = {
      "kubernetes.io/service-account.name" = var.service_account_name
    }
  }
  type = "kubernetes.io/service-account-token"
}

# Create Ubuntu pod for testing
resource "kubernetes_pod" "playground" {
  depends_on = [kubernetes_service_account.playground]

  metadata {
    name      = "ubuntu-test-pod"
    namespace = kubernetes_namespace.playground.metadata[0].name
    labels = {
      "azure.workload.identity/use" = "true"
    }
  }

  spec {
    service_account_name = var.service_account_name

    container {
      name    = "ubuntu"
      image   = "ubuntu:22.04"
      command = ["sleep", "36000"]

      resources {
        requests = {
          cpu    = "100m"
          memory = "128Mi"
        }
      }
    }

    restart_policy = "Never"
  }
}

# Create Kubernetes secret for Datadog API key
resource "kubernetes_secret" "datadog_api_key" {
  depends_on = [kubernetes_namespace.datadog]

  metadata {
    name      = "datadog-api-secret"
    namespace = kubernetes_namespace.datadog.metadata[0].name
  }

  data = {
    api-key = var.datadog_api_key
  }

  type = "Opaque"
}

# Deploy Datadog Agent using Helm
resource "helm_release" "datadog_agent" {
  depends_on = [kubernetes_secret.datadog_api_key]

  name       = "datadog-agent"
  repository = "https://helm.datadoghq.com"
  chart      = "datadog"
  namespace  = kubernetes_namespace.datadog.metadata[0].name

  set {
    name  = "datadog.apiKeyExistingSecret"
    value = kubernetes_secret.datadog_api_key.metadata[0].name
  }
  set {
    name  = "datadog.site"
    value = var.datadog_site
  }

  values = [
    file("${path.module}/../../deploy/datadog-agent.yaml")
  ]
}

# Write cluster kubeconfig to a temp file so local-exec can use it
resource "local_sensitive_file" "kubeconfig" {
  content         = azurerm_kubernetes_cluster.playground.kube_config_raw
  filename        = "${path.module}/kubeconfig.yaml"
  file_permission = "0600"
}

# Deploy playground app — app.yaml is multi-document so we use kubectl apply
# rather than kubernetes_manifest (which only handles single-document YAML).
resource "null_resource" "playground_app" {
  depends_on = [kubernetes_namespace.playground, helm_release.datadog_agent, local_sensitive_file.kubeconfig]

  provisioner "local-exec" {
    command = "kubectl apply -f ${path.module}/../../deploy/app.yaml"
    environment = {
      KUBECONFIG = local_sensitive_file.kubeconfig.filename
    }
  }

  triggers = {
    app_yaml_hash = filemd5("${path.module}/../../deploy/app.yaml")
  }
}
