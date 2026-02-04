# CLAUDE.md

This file provides guidance for Claude Code when working with this repository.

## Project Overview

Infrastructure-as-code (IaC) for a self-hosted Nextcloud instance. Uses **Terraform** for provisioning Hetzner Cloud resources and **PyInfra** for configuration management.

## Project Structure

```
├── terraform/           # Infrastructure provisioning (Hetzner Cloud)
│   ├── main.tf         # Provider config, S3 backend
│   ├── hetzner.tf      # VPS, volume, DNS, storage resources
│   ├── variables.tf    # Input variables
│   └── outputs.tf      # Output values
├── pyinfra/            # Configuration management
│   ├── configure_vps.py  # Main entry point
│   ├── inventory.py      # Host definitions
│   ├── stages/           # Deployment stages (0-3)
│   └── utils/            # Helper functions
├── vps/                # VPS configuration files (deployed to server)
│   ├── caddy/          # Caddy reverse proxy config
│   ├── docker/         # Docker Compose templates (.j2)
│   └── nextcloud/      # Nextcloud scripts (entrypoint, backup)
├── restore.sh          # Backup restoration utility
├── bump.sh             # Version bump script
└── .env                # Environment variables (gitignored)
```

## Common Commands

### Terraform (Infrastructure)

```bash
source .env
cd terraform
terraform init          # Initialize (first time or after provider changes)
terraform plan          # Preview changes
terraform apply         # Apply changes
```

### PyInfra (Configuration)

```bash
uv sync                              # Install Python dependencies
uv run pyinfra/configure_vps.py --fresh  # First deployment (includes bootstrap)
uv run pyinfra/configure_vps.py          # Update existing deployment
uv run pyinfra/configure_vps.py --stage 2-docker  # Run specific stage only
uv run pyinfra/configure_vps.py --auto-approve    # Skip prompts
```

### Validation

```bash
cd terraform && terraform validate   # Validate Terraform config
uv run pyinfra/configure_vps.py --dry  # Dry run PyInfra (doesn't exist yet - use pyinfra directly)
```

## Key Technologies

- **Python 3.12+** with `uv` for dependency management
- **Terraform 1.9.5** with Hetzner Cloud provider
- **PyInfra 3.3+** for server configuration
- **Docker Compose** for services (Nextcloud, PostgreSQL, Redis, Collabora, ClamAV)
- **Caddy** for reverse proxy with automatic HTTPS
- **Restic** for encrypted backups to Hetzner Object Storage

## Environment Variables

All secrets and configuration are in `.env` (see `.env.example` for template). Key variables:
- `HCLOUD_TOKEN` - Hetzner Cloud API token
- `TF_VAR_*` - Terraform variables
- `AWS_*` - S3 credentials for Object Storage
- `POSTGRES_PASSWORD`, `REDIS_PASSWORD`, `NEXTCLOUD_ADMIN_PASSWORD`
- `RESTIC_PASSWORD` - Backup encryption password
- `SMTP_*` - Email configuration (Brevo)

## PyInfra Stages

Stages run in order (0→3). Stage 0 only runs with `--fresh`:

1. **0-bootstrap.py** - Creates deploy user, sets up SSH (runs as root)
2. **1-system.py** - System packages, firewall, unattended upgrades
3. **2-docker.py** - Docker installation, Nextcloud stack deployment
4. **3-caddy.py** - Caddy reverse proxy configuration

## Patterns & Conventions

- Jinja2 templates (`.j2`) in `vps/` are rendered by PyInfra during deployment
- Terraform state stored in Hetzner Object Storage (S3-compatible)
- Docker Compose services defined in `vps/docker/nextcloud.yml.j2`
- Backups run daily at 2 AM via Docker container with Restic

## VPS Access

```bash
ssh deploy@<vps-ip>                    # SSH to VPS
docker logs nextcloud-nextcloud-1      # View Nextcloud logs
docker exec nextcloud-nextcloud-1 su -s /bin/bash www-data -c 'php /var/www/html/occ <command>'  # Run occ commands
```

## Important Notes

- Never commit `.env` - contains secrets
- Run `source .env` before Terraform commands
- Use `--fresh` flag only for initial deployment or to recreate deploy user
- Terraform backend requires manual S3 bucket creation before first use
