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

resource "hetznerdns_zone" "domain" {
  name = var.domain
  ttl  = 3600
}

resource "hetznerdns_record" "drive" {
  zone_id = hetznerdns_zone.domain.id
  type    = "A"
  name    = "drive"
  value   = hcloud_server.vps_reverse_proxy.ipv4_address
}

resource "hetznerdns_record" "letsencrypt" {
  zone_id = hetznerdns_zone.domain.id
  type    = "CAA"
  name    = "@"
  value   = "0 issue \"letsencrypt.org\""
}