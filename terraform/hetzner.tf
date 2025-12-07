resource "hcloud_ssh_key" "main" {
  name       = "hetzner-deployment-key"
  public_key = var.ssh_key_deployment_public
}

resource "hcloud_server" "drive_instance" {
  name        = "drive-instance"
  image       = "ubuntu-24.04"
  server_type = "cpx32"
  location    = "nbg1"
  public_net {
    ipv4_enabled = true
    ipv6_enabled = true
  }
  ssh_keys = [hcloud_ssh_key.main.id]
}

resource "hcloud_volume" "volume1" {
  name      = "volume1"
  size      = 50
  server_id = hcloud_server.drive_instance.id
  automount = true
  format    = "ext4"
}

resource "hcloud_zone" "domain" {
  name = var.domain
  mode = "primary"
  ttl  = 3600
}


resource "hcloud_zone_rrset" "drive" {
  zone    = hcloud_zone.domain.name
  name    = "drive"
  type    = "A"
  ttl     = 3600
  records = [
    { value = hcloud_server.drive_instance.ipv4_address }
  ]
}

resource "hcloud_zone_rrset" "healthcheck" {
  zone    = hcloud_zone.domain.name
  name    = "healthcheck"
  type    = "A"
  ttl     = 3600
  records = [
    { value = hcloud_server.drive_instance.ipv4_address }
  ]
}

resource "hcloud_zone_rrset" "letsencrypt_caa" {
  zone    = hcloud_zone.domain.name
  name    = "@"
  type    = "CAA"
  ttl     = 3600
  records = [
    { value = "0 issue \"letsencrypt.org\"" }
  ]
}

resource "minio_s3_bucket" "nextcloud_backups" {
  bucket = "nextcloud-backups"
  acl    = "private"

  lifecycle {
    prevent_destroy = true
  }
}

resource "minio_s3_bucket_versioning" "nextcloud_backups" {
  bucket = minio_s3_bucket.nextcloud_backups.bucket

  versioning_configuration {
    status = "Enabled"
  }
}