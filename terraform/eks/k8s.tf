# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0

# Kubernetes resources that depend on the EKS cluster being created first

# Create Kubernetes namespace for the playground
resource "kubernetes_namespace" "playground" {
  metadata {
    name = var.playground_namespace
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

