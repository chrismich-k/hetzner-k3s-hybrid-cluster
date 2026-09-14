terraform {
  required_providers {
    hcloud = {
      source = "hetznercloud/hcloud"
    }
  }
  # >= 1.9.0 needed for variable validation blocks that reference other
  # variables (see k3s_primary_master in variables.tf)
  required_version = ">= 1.9.0"
}

provider "hcloud" {
  token = var.hcloud_token
}
