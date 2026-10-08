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
  version    = var.datadog_helm_chart_version
  namespace  = kubernetes_namespace.datadog.metadata[0].name
  
  set {
        name  = "datadog.apiKeyExistingSecret"
        value = kubernetes_secret.datadog_api_key.metadata[0].name
  }
  set {
        name  = "datadog.site"
        value = var.datadog_site
    }
  
  values = concat(
    [file("${path.module}/../../deploy/datadog-agent.yaml")],
    var.extra_agent_values,
  )
}

locals {
  playground_app      = yamldecode(file("${path.module}/../../deploy/app.yaml"))
  langflow_vulnerable = yamldecode(file("${path.module}/../../deploy/langflow-vulnerable.yaml"))

  playground_app_containers = [
    for c in local.playground_app.spec.template.spec.containers :
    c.name == "playground-app" ? merge(c, { image = coalesce(var.playground_image, c.image) }) : c
  ]
  langflow_vulnerable_containers = [
    for c in local.langflow_vulnerable.spec.template.spec.containers :
    c.name == "langflow-vulnerable" ? merge(c, { image = coalesce(var.langflow_image, c.image) }) : c
  ]
}

# Deploy playground app using existing manifest
# Note: deploy/app.yaml contains only the Deployment; the Namespace is managed
# by kubernetes_namespace.playground (and deploy/namespace.yaml for kubectl).
resource "kubernetes_manifest" "playground_app" {
  depends_on = [kubernetes_namespace.playground, helm_release.datadog_agent]

  manifest = merge(local.playground_app, {
    metadata = merge(local.playground_app.metadata, {
      namespace = kubernetes_namespace.playground.metadata[0].name
      name      = "playground-app"
    })
    spec = merge(local.playground_app.spec, {
      template = merge(local.playground_app.spec.template, {
        spec = merge(local.playground_app.spec.template.spec, {
          containers = local.playground_app_containers
        })
      })
    })
  })
}

# Deploy the Langflow CVE-2025-3248 vulnerable container alongside the
# playground app, instrumented with the released ddtrace==4.14.0 build
# and SSI opt-out (see deploy/langflow-vulnerable.yaml).
resource "kubernetes_manifest" "langflow_vulnerable" {
  depends_on = [kubernetes_namespace.playground, helm_release.datadog_agent]

  manifest = merge(local.langflow_vulnerable, {
    metadata = merge(local.langflow_vulnerable.metadata, {
      namespace = kubernetes_namespace.playground.metadata[0].name
    })
    spec = merge(local.langflow_vulnerable.spec, {
      template = merge(local.langflow_vulnerable.spec.template, {
        spec = merge(local.langflow_vulnerable.spec.template.spec, {
          containers = local.langflow_vulnerable_containers
        })
      })
    })
  })
}

resource "kubernetes_service_v1" "langflow" {
  count = var.langflow_service == null ? 0 : 1

  metadata {
    name        = "langflow-vulnerable"
    namespace   = kubernetes_namespace.playground.metadata[0].name
    annotations = var.langflow_service.annotations
  }

  spec {
    type                        = var.langflow_service.type
    selector                    = local.langflow_vulnerable.spec.selector.matchLabels
    load_balancer_source_ranges = var.langflow_service.source_ranges

    port {
      name        = "http"
      port        = 7860
      target_port = "http"
    }
  }
}

