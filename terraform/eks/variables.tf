# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0

variable "region" {
  description = "AWS region"
  type        = string
  default     = "eu-west-3"
}

variable "playground_namespace" {
  description = "Namespace for the playground apps"
  type        = string
  default     = "playground"
}

variable "service_account_name" {
  description = "Service account name"
  type        = string
  default     = "playground-sa"
} 