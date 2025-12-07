variable "environment" {
  type        = string
  description = "Environment in which to deploy resources"
  default     = "prod"
}

variable "default_tags" {
  type        = list(string)
  description = "Default tags to provide to resources where suppored"
  default     = ["tf_managed"]
}

variable "domain" {
  type        = string
  description = "Domain to be used for reverse proxy and DNS records"
  default     = "dobbertjeduik.nl"
}

variable "hcloud_token" {
  type        = string
  description = "Hetzner Cloud token"
  sensitive   = true
}

variable "ssh_key_deployment_public" {
  type        = string
  description = "Public key for deployments on Hetzner"
}

variable "hetzner_s3_access_key" {
  type        = string
  description = "Hetzner Object Storage access key"
  sensitive   = true
}

variable "hetzner_s3_secret_key" {
  type        = string
  description = "Hetzner Object Storage secret key"
  sensitive   = true
}

variable "hetzner_region" {
  type        = string
  description = "Hetzner region for Object Storage and other resources"
  default     = "nbg1"
}