output "vps_ip" {
  description = "IPv4 for the VPS"
  value       = hcloud_server.drive_instance.ipv4_address
}

output "volume_device" {
  value = "/dev/disk/by-id/scsi-0HC_Volume_${hcloud_volume.volume1.id}"
}
