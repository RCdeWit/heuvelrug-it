resource "random_id" "suffix" {
  byte_length = 3  # 3 bytes = 6 hex characters
}

resource "hcloud_ssh_key" "main" {
  name       = "${var.project_name}-${random_id.suffix.hex}-deployment-key"
  public_key = var.ssh_key_deployment_public
}

# Firewall - SSH blocked from public internet, only accessible via Tailscale
resource "hcloud_firewall" "nextcloud" {
  name = "${var.project_name}-${random_id.suffix.hex}-firewall"

  # Allow HTTP (for ACME challenges and redirect to HTTPS)
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "80"
    source_ips = ["0.0.0.0/0", "::/0"]
  }

  # Allow HTTPS
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "443"
    source_ips = ["0.0.0.0/0", "::/0"]
  }

  # Allow ICMP (ping) for diagnostics
  rule {
    direction  = "in"
    protocol   = "icmp"
    source_ips = ["0.0.0.0/0", "::/0"]
  }

  # Allow UDP for TURN server (Nextcloud Talk)
  rule {
    direction  = "in"
    protocol   = "udp"
    port       = "3478"
    source_ips = ["0.0.0.0/0", "::/0"]
  }

  # Allow UDP range for TURN relay (coturn)
  rule {
    direction  = "in"
    protocol   = "udp"
    port       = "49152-65535"
    source_ips = ["0.0.0.0/0", "::/0"]
  }
}

resource "hcloud_server" "drive_instance" {
  name        = "${var.project_name}-${random_id.suffix.hex}-nextcloud"
  image       = "ubuntu-24.04"
  server_type = "cpx42"
  location    = "nbg1"
  public_net {
    ipv4_enabled = true
    ipv6_enabled = true
  }
  ssh_keys     = [hcloud_ssh_key.main.id]
  firewall_ids = [hcloud_firewall.nextcloud.id]

  lifecycle {
    prevent_destroy = true
  }

  # Cloud-init: Install Tailscale before any SSH-based provisioning
  user_data = <<-EOF
    #!/bin/bash
    set -e

    # Install Tailscale
    curl -fsSL https://tailscale.com/install.sh | sh

    # Authenticate and bring up Tailscale with the VPS tag
    # Hostname matches the server name for consistency
    tailscale up --auth-key=${var.tailscale_auth_key} --hostname=${var.project_name}-${random_id.suffix.hex}-nextcloud --advertise-tags=tag:vps-external

    # Wait for Tailscale to be fully connected
    sleep 5
    tailscale status

    # Configure UFW firewall (SSH only accessible via Tailscale)
    ufw allow OpenSSH
    ufw default deny incoming
    ufw default allow outgoing
    ufw --force enable
  EOF
}

resource "hcloud_volume" "volume1" {
  name      = "${var.project_name}-${random_id.suffix.hex}-data"
  size      = 50
  server_id = hcloud_server.drive_instance.id
  automount = true
  format    = "ext4"

  lifecycle {
    prevent_destroy = true
  }
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

resource "hcloud_zone_rrset" "office" {
  zone    = hcloud_zone.domain.name
  name    = "office"
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

# Brevo email authentication records
# These records are required for Brevo to send emails on behalf of your domain
# Get the DKIM keys from: Brevo Dashboard -> Settings -> Senders & IP -> Add Domain

# Root domain TXT records - includes SPF and optional Brevo verification code
# Note: Records are sorted alphabetically to match Hetzner API ordering
resource "hcloud_zone_rrset" "brevo_txt" {
  zone    = hcloud_zone.domain.name
  name    = "@"
  type    = "TXT"
  ttl     = 3600
  records = concat(
    var.brevo_verification_code != "" ? [
      { value = "\"${var.brevo_verification_code}\"" }
    ] : [],
    [
      { value = "\"v=spf1 include:spf.brevo.com ~all\"" }
    ]
  )
}

# DKIM records - cryptographic signatures for email authentication
# Brevo provides CNAME records that point to their DKIM infrastructure
# Only create these if the DKIM keys are provided (not empty)

resource "hcloud_zone_rrset" "brevo_dkim1" {
  count   = var.brevo_dkim_key1 != "" ? 1 : 0
  zone    = hcloud_zone.domain.name
  name    = "brevo1._domainkey"
  type    = "CNAME"
  ttl     = 3600
  records = [
    { value = var.brevo_dkim_key1 }
  ]
}

resource "hcloud_zone_rrset" "brevo_dkim2" {
  count   = var.brevo_dkim_key2 != "" ? 1 : 0
  zone    = hcloud_zone.domain.name
  name    = "brevo2._domainkey"
  type    = "CNAME"
  ttl     = 3600
  records = [
    { value = var.brevo_dkim_key2 }
  ]
}

# DMARC record - policy for handling emails that fail authentication
# This tells receiving servers what to do with emails that fail SPF/DKIM checks
resource "hcloud_zone_rrset" "dmarc" {
  zone    = hcloud_zone.domain.name
  name    = "_dmarc"
  type    = "TXT"
  ttl     = 3600
  records = [
    { value = "\"v=DMARC1; p=none; rua=mailto:dmarc@${var.domain}\"" }
  ]
}

# Nextcloud Whiteboard WebSocket server
resource "hcloud_zone_rrset" "whiteboard" {
  zone    = hcloud_zone.domain.name
  name    = "whiteboard"
  type    = "A"
  ttl     = 3600
  records = [
    { value = hcloud_server.drive_instance.ipv4_address }
  ]
}

# Nextcloud Talk - DNS records for video conferencing components

# TURN server - points to main server (coturn runs on host network)
resource "hcloud_zone_rrset" "turn" {
  zone    = hcloud_zone.domain.name
  name    = "turn"
  type    = "A"
  ttl     = 3600
  records = [
    { value = hcloud_server.drive_instance.ipv4_address }
  ]
}

# Signaling server (HPB) - for high performance backend
resource "hcloud_zone_rrset" "signaling" {
  zone    = hcloud_zone.domain.name
  name    = "signaling"
  type    = "A"
  ttl     = 3600
  records = [
    { value = hcloud_server.drive_instance.ipv4_address }
  ]
}

resource "minio_s3_bucket" "nextcloud_backups" {
  bucket = "${var.project_name}-${random_id.suffix.hex}-nextcloud-backups"
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