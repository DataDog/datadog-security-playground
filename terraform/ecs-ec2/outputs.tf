# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0

output "region" {
  description = "AWS region"
  value       = var.region
}

output "cluster_name" {
  description = "ECS cluster name"
  value       = aws_ecs_cluster.main.name
}

output "instance_id" {
  description = "EC2 container instance ID"
  value       = aws_instance.ecs.id
}

output "ssm_session_command" {
  description = "Open a shell on the container instance (no SSH key required)"
  value       = "aws ssm start-session --region ${var.region} --target ${aws_instance.ecs.id}"
}

output "app_port_forward_command" {
  description = "Forward the playground app to localhost so scenarios/*/detonate.sh works unchanged"
  value = join(" ", [
    "aws ssm start-session --region ${var.region} --target ${aws_instance.ecs.id}",
    "--document-name AWS-StartPortForwardingSession",
    "--parameters '{\"portNumber\":[\"${local.app_port}\"],\"localPortNumber\":[\"${local.app_port}\"]}'",
  ])
}

output "app_exec_command" {
  description = "Open a shell inside the playground app container. AWS supports ECS Exec only on ECS-optimized AMIs, so on this Ubuntu host prefer app_exec_fallback_command."
  value = join(" ", [
    "aws ecs execute-command --region ${var.region}",
    "--cluster ${aws_ecs_cluster.main.name}",
    "--task <task-id>",
    "--container playground-app --interactive --command /bin/sh",
  ])
}

output "app_exec_fallback_command" {
  description = "Shell into the app container over an SSM host session. Works regardless of ECS Exec support."
  value = join(" ", [
    "aws ssm start-session --region ${var.region} --target ${aws_instance.ecs.id}",
    "--document-name AWS-StartInteractiveCommand",
    "--parameters '{\"command\":[\"sudo docker exec -it $(sudo docker ps -qf name=playground-app) /bin/sh\"]}'",
  ])
}
