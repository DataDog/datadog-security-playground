# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0

output "cluster_endpoint" {
  description = "Endpoint for EKS control plane"
  value       = module.eks.cluster_endpoint
}

output "cluster_security_group_id" {
  description = "Security group ids attached to the cluster control plane"
  value       = module.eks.cluster_security_group_id
}

output "region" {
  description = "AWS region"
  value       = var.region
}

output "cluster_name" {
  description = "Kubernetes Cluster Name"
  value       = module.eks.cluster_name
}

output "langflow_lb_hostname" {
  description = "Load balancer hostname of the langflow-vulnerable Service, when langflow_service.type is LoadBalancer"
  value       = try(kubernetes_service_v1.langflow[0].status[0].load_balancer[0].ingress[0].hostname, null)
}
