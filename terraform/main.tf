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

    minio = {
      source  = "aminueza/minio"
      version = "~> 3.3"
    }
  }
}

provider "hcloud" {
  token = var.hcloud_token
}

provider "minio" {
  minio_server   = "fsn1.your-objectstorage.com"
  minio_user     = var.hetzner_s3_access_key
  minio_password = var.hetzner_s3_secret_key
  minio_ssl      = true
}