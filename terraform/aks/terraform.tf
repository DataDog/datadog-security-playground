# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0

terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }

    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.30.0"
    }

    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.13.0"
    }
  }

  required_version = "~> 1.3"
}
