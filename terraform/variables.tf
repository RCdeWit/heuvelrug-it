variable "project_name" {
  type        = string
  description = "Client/project name used as prefix for all resources"
  default     = "heuvelrug"
}

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

# Brevo (email provider) DNS verification records
# These are provided by Brevo when you add your domain for verification
# Get these from: Brevo Dashboard -> Settings -> Senders & IP -> Add Domain

variable "brevo_verification_code" {
  type        = string
  description = "Brevo domain verification code (from code-verification TXT record)"
  default     = ""
  sensitive   = false
}

variable "brevo_dkim_key1" {
  type        = string
  description = "Brevo DKIM CNAME target 1 (from mail._domainkey CNAME record)"
  default     = ""
  sensitive   = false
}

variable "brevo_dkim_key2" {
  type        = string
  description = "Brevo DKIM CNAME target 2 (from mail2._domainkey CNAME record)"
  default     = ""
  sensitive   = false
}

# Tailscale configuration for SSH-only-via-Tailnet
variable "tailscale_auth_key" {
  type        = string
  description = "Tailscale auth key for cloud-init provisioning. Generate at: Tailscale Admin -> Settings -> Keys"
  sensitive   = true
}