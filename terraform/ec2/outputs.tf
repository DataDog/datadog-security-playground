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

output "load_policy_document_name" {
  description = "SSM document that loads a local CWS policy file. Used by ./load-policy.sh."
  value       = aws_ssm_document.load_cws_policy.name
}

output "load_policy_command" {
  description = "Load a policy file onto the instance"
  value       = "./load-policy.sh <path-to-file>.policy"
}
