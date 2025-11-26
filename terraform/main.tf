terraform {
  required_version = "1.9.5"

  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "~> 1.45"
    }

    hetznerdns = {
      source  = "germanbrew/hetznerdns"
      version = "3.4.3"
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

provider "hetznerdns" {
  api_token = var.hetznerdns_token
}