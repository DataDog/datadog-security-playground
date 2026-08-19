# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0

output "region" {
  description = "AWS region"
  value       = var.region
}

output "instance_id" {
  description = "EC2 instance ID"
  value       = aws_instance.playground.id
}

output "instance_name" {
  description = "Name tag of the instance"
  value       = local.name
}

output "ssm_session_command" {
  description = "Open a shell on the instance (no SSH key required)"
  value       = "aws ssm start-session --region ${var.region} --target ${aws_instance.playground.id}"
}


