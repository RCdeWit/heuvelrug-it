resource "hcloud_ssh_key" "main" {
  name       = "hetzner-deployment-key"
  public_key = var.ssh_key_deployment_public
}

resource "hcloud_server" "vps_reverse_proxy" {
  name        = "reverse-proxy-vps"
  image       = "ubuntu-24.04"
  server_type = "cpx32"
  location    = "nbg1"
  public_net {
    ipv4_enabled = true
    ipv6_enabled = true
  }
  ssh_keys = [hcloud_ssh_key.main.id]
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
    { value = hcloud_server.vps_reverse_proxy.ipv4_address }
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