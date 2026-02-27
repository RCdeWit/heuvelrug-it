terraform {
  required_version = "1.14.6"

  backend "s3" {
    bucket = "heuvelrugterraformstate"
    key    = "terraform.tfstate"
    region = "nbg1"  # Must match bucket region - update manually if changed

    endpoints = {
      s3 = "https://nbg1.your-objectstorage.com"  # Must match bucket region
    }

    # Required for Hetzner Object Storage (Ceph S3 compatibility)
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    use_path_style              = true
    skip_s3_checksum            = true
  }

  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "~> 1.45"
    }

    minio = {
      source  = "aminueza/minio"
      version = "~> 3.3"
    }

    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }

    tailscale = {
      source  = "tailscale/tailscale"
      version = "0.28.0"
    }
  }
}

provider "hcloud" {
  token = var.hcloud_token
}

provider "minio" {
  minio_server   = "${var.hetzner_region}.your-objectstorage.com"
  minio_region   = var.hetzner_region
  minio_user     = var.hetzner_s3_access_key
  minio_password = var.hetzner_s3_secret_key
  minio_ssl      = true
}