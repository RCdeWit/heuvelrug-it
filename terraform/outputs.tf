output "vps_ip" {
  description = "IPv4 for the VPS"
  value       = hcloud_server.drive_instance.ipv4_address
}

output "volume_device" {
  value = "/dev/disk/by-id/scsi-0HC_Volume_${hcloud_volume.volume1.id}"
}

output "s3_endpoint" {
  description = "Hetzner Object Storage endpoint"
  value       = "https://${var.hetzner_region}.your-objectstorage.com"
}

output "s3_region" {
  description = "Hetzner Object Storage region"
  value       = var.hetzner_region
}

output "s3_bucket" {
  description = "Backup bucket name"
  value       = minio_s3_bucket.nextcloud_backups.bucket
}

output "project_prefix" {
  description = "Project prefix used for resource naming"
  value       = "${var.project_name}-${random_id.suffix.hex}"
}

output "random_suffix" {
  description = "Random suffix used in resource names"
  value       = random_id.suffix.hex
}

output "tailnet_hostname" {
  description = "Tailscale hostname for SSH access (set VPS_TAILNET_HOSTNAME to this)"
  value       = "${var.project_name}-${random_id.suffix.hex}-nextcloud"
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
