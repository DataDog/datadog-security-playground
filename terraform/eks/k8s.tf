# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0

# Kubernetes resources that depend on the EKS cluster being created first

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

# Create Kubernetes service account
resource "kubernetes_service_account" "playground" {
  metadata {
    name      = var.service_account_name
    namespace = kubernetes_namespace.playground.metadata[0].name
    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.playground.arn
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
  }
  
  spec {
    service_account_name = var.service_account_name
    
    container {
      name  = "ubuntu"
      image = "ubuntu:22.04"
      command = ["sleep", "36000"]  # Keep the pod running for 10 hours
      
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

# Deploy playground app using existing manifest
resource "kubernetes_manifest" "playground_app" {
  depends_on = [kubernetes_namespace.playground, helm_release.datadog_agent]
  
  manifest = merge(
    yamldecode(templatefile("${path.module}/../../deploy/app.yaml", {
      dd_api_key = var.datadog_api_key
      dd_site    = var.datadog_site
    })),
    {
      metadata = merge(
        yamldecode(templatefile("${path.module}/../../deploy/app.yaml", {
          dd_api_key = var.datadog_api_key
          dd_site    = var.datadog_site
        })).metadata,
        {
          namespace = kubernetes_namespace.playground.metadata[0].name
          name = "playground-app"
        }
      )
    }
  )
}

