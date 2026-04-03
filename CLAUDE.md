# CLAUDE.md

This file provides guidance for Claude Code when working with this repository.

## Project Overview

Infrastructure-as-code (IaC) for a self-hosted Nextcloud instance. Uses **Terraform** for provisioning Hetzner Cloud resources and **PyInfra** for configuration management.

## Project Structure

```
├── terraform/                # Infrastructure provisioning (Hetzner Cloud)
│   ├── main.tf              # Provider config, S3 backend
│   ├── hetzner.tf           # VPS, volume, DNS, storage resources
│   ├── variables.tf         # Input variables
│   ├── outputs.tf           # Output values
│   ├── backend.hcl.example  # Per-tenant backend config template (committed)
│   └── backend.hcl          # Resolved per-tenant backend config (gitignored)
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
├── .env.1password      # 1Password template for environment variables (committed)
├── .env.example        # Human-readable reference with documentation
└── .env                # Resolved local file (gitignored, generated via op inject)
```

## Common Commands

### Environment Setup

```bash
op inject -i .env.1password -o .env   # Generate .env from 1Password
source .env                           # Load environment variables
```

### Terraform (Infrastructure)

```bash
source .env
cd terraform
cp backend.hcl.example backend.hcl   # First time: create per-tenant backend config
# Edit backend.hcl: set key = "tenants/<tenant-name>/terraform.tfstate"
terraform init -backend-config=backend.hcl  # Initialize with per-tenant state key
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
- **Terraform 1.14.8** with Hetzner Cloud provider
- **PyInfra 3.3+** for server configuration
- **Docker Compose** for services (Nextcloud, PostgreSQL, Redis, Collabora, ClamAV, Whiteboard)
- **Caddy** for reverse proxy with automatic HTTPS
- **Restic** for encrypted backups to Hetzner Object Storage
- **Tailscale** for mesh VPN (SSH access and private networking - public SSH is blocked)
- **Komodo Periphery** for Docker container monitoring/management

## Environment Variables

Secrets are stored in 1Password (Vault: `Infra`, Item: `GitHub.RCdeWit.heuvelrug-it`) and managed via two files:

- **`.env.1password`** - Template with `op://` references; committed to the repo
- **`.env`** - Resolved local file; gitignored, generated via `op inject`

To set up locally:

```bash
op inject -i .env.1password -o .env
source .env
```

See `.env.example` for full documentation of each variable.

## PyInfra Stages

Stages run in order (0→3). Stage 0 only runs with `--fresh`:

1. **0-bootstrap.py** - Creates deploy user, sets up SSH (runs as root)
2. **1-system.py** - System packages, firewall, unattended upgrades, Tailscale
3. **2-docker.py** - Docker installation, Nextcloud stack deployment, Komodo Periphery
4. **3-caddy.py** - Caddy reverse proxy configuration

## Patterns & Conventions

- Jinja2 templates (`.j2`) in `vps/` are rendered by PyInfra during deployment
- Terraform state stored in Hetzner Object Storage (S3-compatible), namespaced per tenant
- Docker Compose services defined in `vps/docker/nextcloud.yml.j2`
- Backups run daily at 2 AM via Docker container with Restic
- Container names and deploy path are derived from `COMPOSE_PROJECT_NAME` / `NEXTCLOUD_DIR` env vars
- `2-docker.py` and `3-caddy.py` hard-exit if `TF_VAR_domain` is unset (prevents deploying with wrong domain)

## Multi-Tenant Support

This repo is designed to support multiple tenants sharing the same codebase and S3 bucket:

- **`TF_VAR_project_name`** — prefixes all Hetzner resources (server, volume, DNS, storage)
- **`TF_VAR_domain`** — per-tenant domain; must be set before running PyInfra or Terraform
- **`NEXTCLOUD_DIR`** — deploy path on VPS (default: `/opt/nextcloud`); overridable per tenant
- **`COMPOSE_PROJECT_NAME`** — Docker project name; container names are derived from this
- **`HETZNER_S3_DOMAIN`** — S3 storage domain suffix; overridable if bucket region differs
- **Terraform state** — each tenant gets a unique key path in the shared S3 bucket via `backend.hcl`
- **VPS and data volume** have `prevent_destroy = true` to guard against accidental `terraform destroy`

## VPS Access

SSH is only accessible via Tailscale (public SSH is blocked by Hetzner firewall). The Tailscale hostname is auto-detected from Terraform output.

```bash
ssh deploy@$(cd terraform && terraform output -raw tailnet_hostname)  # SSH to VPS
docker logs nextcloud-nextcloud-1      # View Nextcloud logs
docker exec nextcloud-nextcloud-1 su -s /bin/bash www-data -c 'php /var/www/html/occ <command>'  # Run occ commands
```

## Network Security

- **Hetzner Firewall**: Blocks SSH (port 22) from public internet; only HTTP/HTTPS/ICMP/TURN allowed
- **Tailscale**: Provides SSH access via mesh VPN (`tag:vps-external`)
- **UFW**: Host firewall allows OpenSSH (accessible only via Tailscale)
- **Cloud-init**: Tailscale is installed during VPS provisioning, before any SSH-based deployment

## Komodo Integration

Komodo Periphery runs as a Docker container for remote container management.

- **Periphery port**: 8120 (bound to Tailscale IP only, not exposed to internet)
- **Komodo access**: NAS (`tag:nas`) can reach VPS on port 8120 for container orchestration

To add this server to Komodo Core, register it using its Tailscale hostname or IP on port 8120.

## Important Notes

- Never commit `.env` or `terraform/backend.hcl` — both contain tenant-specific secrets/config
- Run `source .env` before Terraform commands
- Use `--fresh` flag only for initial deployment or to recreate deploy user
- Terraform backend requires manual S3 bucket creation before first use
- Always use `terraform init -backend-config=backend.hcl` (not bare `terraform init`) to load the correct per-tenant state key
- After `terraform apply` for a new VPS, wait ~1-2 min for cloud-init (Tailscale) before running PyInfra
- `TF_VAR_domain` **must** be set in the environment before running PyInfra — stages will hard-exit if missing
