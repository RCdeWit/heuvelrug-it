terraform {
  required_version = "1.9.5"

  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "~> 1.45"
    }

    tailscale = {
      source  = "tailscale/tailscale"
      version = "0.15.0"
    }
  }
}

provider "hcloud" {
  token = var.hcloud_token
}