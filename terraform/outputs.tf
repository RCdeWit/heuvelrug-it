output "vps_ip" {
  description = "IPv4 for the VPS"
  value       = hcloud_server.drive_instance.ipv4_address
}