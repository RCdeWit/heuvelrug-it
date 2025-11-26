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

variable "hetznerdns_token" {
  type        = string
  description = "Hetzner DNS API token"
  sensitive   = true
}

variable "ssh_key_deployment_public" {
  type        = string
  description = "Public key for deployments on Hetzner"
}