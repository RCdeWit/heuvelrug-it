output "vps_ip" {
  description = "IPv4 for the VPS"
  value       = hcloud_server.drive_instance.ipv4_address
}

output "volume_device" {
  value = "/dev/disk/by-id/scsi-0HC_Volume_${hcloud_volume.volume1.id}"
}

output "s3_endpoint" {
  description = "Hetzner Object Storage endpoint"
  value       = "https://nbg1.your-objectstorage.com"
}

output "s3_bucket" {
  description = "Backup bucket name"
  value       = minio_s3_bucket.nextcloud_backups.bucket
}

output "s3_access_key" {
  description = "S3 access key"
  value       = var.hetzner_s3_access_key
  sensitive   = true
}

output "s3_secret_key" {
  description = "S3 secret key"
  value       = var.hetzner_s3_secret_key
  sensitive   = true
}
