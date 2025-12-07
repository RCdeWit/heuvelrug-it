# GL/PvdA Heuvelrug IT

[![Deploy Infra](https://github.com/RCdeWit/heuvelrug-it/actions/workflows/deploy.yml/badge.svg?branch=main)](https://github.com/RCdeWit/heuvelrug-it/actions/workflows/deploy.yml)

Infrastructure-as-code (IaC) for GL/PvdA Heuvelrug's self-hosted Nextcloud instance. Uses Terraform for provisioning cloud resources on Hetzner and PyInfra for configuration management.

## Architecture

```text
┌─────────────────────────────────────────────────────────────┐
│ Hetzner Cloud (Nuremberg - nbg1)                            │
│                                                              │
│  ┌──────────────────────────────────────────────────────┐  │
│  │ VPS (cpx32 - Ubuntu 24.04)                           │  │
│  │                                                       │  │
│  │  ┌─────────────┐      ┌──────────────────────────┐  │  │
│  │  │   Caddy     │─────▶│  Nextcloud (Docker)      │  │  │
│  │  │  (HTTPS)    │      │  - Web Application       │  │  │
│  │  └─────────────┘      │  - PostgreSQL Database   │  │  │
│  │                       │  - Redis Cache           │  │  │
│  │                       └──────────────────────────┘  │  │
│  │                                                       │  │
│  │  ┌──────────────────────────────────────────────┐   │  │
│  │  │  Backup Service (Docker)                     │   │  │
│  │  │  - Restic backups (daily 2 AM)              │   │  │
│  │  │  - Database dumps                            │   │  │
│  │  │  - Encrypted, deduplicated                   │   │  │
│  │  └──────────────────────────────────────────────┘   │  │
│  │                                                       │  │
│  │  ┌──────────────────────────────────────────────┐   │  │
│  │  │  Attached Volume (50 GB)                     │   │  │
│  │  │  - Nextcloud user data                       │   │  │
│  │  │  - PostgreSQL database files                 │   │  │
│  │  │  - Application files                         │   │  │
│  │  └──────────────────────────────────────────────┘   │  │
│  └───────────────────────────────────────────────────────┘  │
│                                                              │
│  ┌──────────────────────────────────────────────────────┐  │
│  │ Object Storage (S3-compatible)                       │  │
│  │  - Terraform state (heuvelrugterraformstate)        │  │
│  │  - Nextcloud backups (nextcloud-backups)            │  │
│  └──────────────────────────────────────────────────────┘  │
│                                                              │
│  ┌──────────────────────────────────────────────────────┐  │
│  │ DNS (dobbertjeduik.nl)                               │  │
│  │  - drive.dobbertjeduik.nl → VPS                      │  │
│  │  - healthcheck.dobbertjeduik.nl → VPS                │  │
│  └──────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

## Components

### Infrastructure
- **Hetzner Cloud VPS**: cpx32 instance (8 vCPU, 16 GB RAM) in Nuremberg
- **Hetzner Volume**: 50 GB persistent storage for data
- **Hetzner Object Storage**: S3-compatible storage for backups and Terraform state
- **Hetzner DNS**: Managed DNS for dobbertjeduik.nl

### Application Stack
- **Caddy**: Reverse proxy with automatic HTTPS via Let's Encrypt
- **Nextcloud**: Self-hosted file sync and collaboration platform
  - **PostgreSQL 15**: Database backend
  - **Redis 7**: Caching and file locking
- **Restic**: Encrypted, deduplicated backups to Object Storage

### Backup Strategy
- **Frequency**: Daily at 2 AM (during maintenance window)
- **Retention**:
  - Daily backups: 30 days
  - Weekly backups: 52 weeks (1 year)
  - Monthly backups: 24 months (2 years)
- **Method**: Incremental, encrypted, deduplicated via Restic
- **Storage**: Hetzner Object Storage (S3-compatible)
- **What's backed up**:
  - PostgreSQL database dumps
  - Nextcloud user data
  - Application configuration

## Prerequisites

### Required Accounts
- Hetzner Cloud account with API token
- Hetzner Object Storage with access keys

### Local Requirements
- Terraform 1.9.5+
- Python 3.12+ with uv
- SSH key pair for deployment

## Deployment

### 1. Initial Setup

Clone the repository and set up environment:

```bash
git clone <repository-url>
cd heuvelrug-it
cp .env.example .env
```

Edit `.env` and fill in all required credentials:
- Hetzner Cloud API token
- S3 access keys for Object Storage
- SSH public key
- Generate passwords for PostgreSQL, Redis, Nextcloud, and Restic

### 2. Configure Domain Nameservers

Point your domain to Hetzner's authoritative nameservers:
1. Log in to your domain registrar
2. Update nameservers to Hetzner's DNS:
   - `hydrogen.ns.hetzner.com`
   - `oxygen.ns.hetzner.com`
   - `helium.ns.hetzner.de`
3. Wait for DNS propagation (can take up to 48 hours)

For detailed instructions, see [Hetzner's authoritative nameservers documentation](https://docs.hetzner.com/dns-console/dns/general/authoritative-name-servers/).

### 3. Create Object Storage Buckets

Via Hetzner Cloud Console:
1. Navigate to Object Storage
2. Create bucket `heuvelrugterraformstate` in nbg1 (Nuremberg)
3. Create access keys and add to `.env`

### 4. Provision Infrastructure

```bash
# Load environment variables
source .env

# Initialize Terraform and migrate state to S3
cd terraform
terraform init -migrate-state

# Review and apply infrastructure changes
terraform plan
terraform apply

# Note the VPS IP address from outputs
```

### 5. Configure VPS

```bash
# Return to project root
cd ..

# Install Python dependencies
uv sync

# First-time deployment (creates deploy user)
uv run pyinfra/configure_vps.py --fresh

# Or for updates to existing deployment
uv run pyinfra/configure_vps.py
```

### 6. Verify Deployment

1. Visit `https://drive.dobbertjeduik.nl`
2. Log in with Nextcloud admin credentials from `.env`
3. Check backup service: `ssh deploy@<vps-ip> "docker logs nextcloud-backup-1"`

## Backup Management

### Monitoring Backups

```bash
# SSH into VPS
ssh deploy@<vps-ip>

# View backup logs
docker logs -f nextcloud-backup-1

# List all snapshots
docker exec nextcloud-backup-1 restic snapshots

# Show repository statistics
docker exec nextcloud-backup-1 restic stats --mode restore-size

# Check last backup status
docker exec nextcloud-backup-1 restic snapshots --last
```

### Manual Backup

```bash
# Trigger immediate backup
ssh deploy@<vps-ip>
docker exec nextcloud-backup-1 /bin/sh /backup.sh
```

### Backup Retention Policy

Restic automatically prunes old backups according to this schedule:
- **Daily**: Last 30 daily backups
- **Weekly**: Last 52 weekly backups (1 year)
- **Monthly**: Last 24 monthly backups (2 years)

Weekly integrity checks run automatically every Sunday.

## Disaster Recovery

### Restoring from Backup

#### 1. List Available Snapshots

```bash
# SSH into VPS or backup container
docker exec -it nextcloud-backup-1 /bin/sh

# List all snapshots
restic snapshots

# List snapshots with specific tags
restic snapshots --tag nextcloud
```

#### 2. Restore Files

```bash
# Restore entire snapshot to temporary location
restic restore <snapshot-id> --target /tmp/restore

# Restore specific files/directories
restic restore <snapshot-id> \
  --target /tmp/restore \
  --include /mnt/data/ncdata/admin/files

# Restore database dump
restic restore <snapshot-id> \
  --target /tmp/restore \
  --include /backup/nextcloud_db.sql
```

#### 3. Restore Database

```bash
# Copy restored database dump to container
docker cp /tmp/restore/backup/nextcloud_db.sql nextcloud-nextcloud-db-1:/tmp/

# Enable maintenance mode
docker exec nextcloud-nextcloud-1 \
  su -s /bin/bash www-data -c 'php /var/www/html/occ maintenance:mode --on'

# Restore database
docker exec nextcloud-nextcloud-db-1 \
  psql -U nextcloud -d nextcloud < /tmp/nextcloud_db.sql

# Disable maintenance mode
docker exec nextcloud-nextcloud-1 \
  su -s /bin/bash www-data -c 'php /var/www/html/occ maintenance:mode --off'
```

#### 4. Complete Disaster Recovery

For complete infrastructure loss:

```bash
# 1. Provision fresh infrastructure
source .env
cd terraform
terraform apply

# 2. Deploy base configuration
cd ..
uv run pyinfra/configure_vps.py --fresh

# 3. Stop Nextcloud services
ssh deploy@<vps-ip>
cd /opt/nextcloud
docker compose down

# 4. Restore data from backup (on VPS)
# Install restic
apt-get install restic

# Configure environment
export AWS_ACCESS_KEY_ID=<from .env>
export AWS_SECRET_ACCESS_KEY=<from .env>
export RESTIC_PASSWORD=<from .env>
export RESTIC_REPO="s3:https://nbg1.your-objectstorage.com/nextcloud-backups"

# List snapshots and choose latest
restic snapshots

# Restore to mounted volume
restic restore <snapshot-id> --target /

# 5. Start services
cd /opt/nextcloud
docker compose up -d

# 6. Verify and run maintenance
docker exec nextcloud-nextcloud-1 \
  su -s /bin/bash www-data -c 'php /var/www/html/occ maintenance:repair'
```

## Maintenance

### Updating Nextcloud

```bash
# SSH into VPS
ssh deploy@<vps-ip>

# Pull latest image
cd /opt/nextcloud
docker compose pull nextcloud

# Restart with new image
docker compose up -d nextcloud
```

### Updating System Packages

```bash
# Via PyInfra (from local machine)
uv run pyinfra/configure_vps.py

# Or manually on VPS
ssh deploy@<vps-ip>
sudo apt update && sudo apt upgrade -y
```

### Monitoring Disk Usage

```bash
# Check volume usage
ssh deploy@<vps-ip> df -h

# Check Docker disk usage
ssh deploy@<vps-ip> docker system df

# Check Nextcloud storage usage
# Visit: Settings > Administration > System
```

### Checking Service Health

```bash
# All services status
ssh deploy@<vps-ip>
docker ps
docker compose -f /opt/nextcloud/docker-compose.yml ps

# Nextcloud logs
docker logs nextcloud-nextcloud-1

# Database logs
docker logs nextcloud-nextcloud-db-1

# Caddy logs
sudo journalctl -u caddy -f
```

## Development

### Local Testing

```bash
# Validate Terraform configuration
cd terraform
terraform validate
terraform plan

# Test PyInfra configuration (dry run)
cd ..
uv run pyinfra/configure_vps.py --dry
```

### Project Structure

```text
.
├── terraform/           # Infrastructure provisioning
│   ├── main.tf         # Terraform configuration
│   ├── variables.tf    # Input variables
│   ├── outputs.tf      # Output values
│   └── hetzner.tf      # Hetzner resources
├── pyinfra/            # Configuration management
│   ├── stages/         # Deployment stages
│   │   ├── 0-bootstrap.py
│   │   ├── 1-docker.py
│   │   └── 2-caddy.py
│   └── configure_vps.py
├── vps/                # VPS configuration files
│   ├── caddy/          # Caddy reverse proxy config
│   ├── docker/         # Docker Compose templates
│   └── nextcloud/      # Nextcloud-specific configs
│       ├── nextcloud.config.php
│       ├── nextcloud-entrypoint.sh
│       └── backup.sh
├── .env                # Environment variables (gitignored)
├── .env.example        # Template for environment variables
└── README.md           # This file
```

## Security Considerations

- All services run behind Caddy with automatic HTTPS
- Backups are encrypted with Restic before upload
- S3 buckets have `prevent_destroy` lifecycle rule
- Object Storage versioning enabled for backup bucket
- Passwords generated with `openssl rand -base64 32`
- SSH key-based authentication only
- PostgreSQL and Redis not exposed externally

## Troubleshooting

### Backup Failures

```bash
# Check backup container logs
docker logs nextcloud-backup-1

# Verify S3 credentials
docker exec nextcloud-backup-1 env | grep AWS

# Test Restic connection
docker exec nextcloud-backup-1 restic snapshots

# Check disk space
df -h
```

### Nextcloud Issues

```bash
# Run Nextcloud maintenance
docker exec nextcloud-nextcloud-1 \
  su -s /bin/bash www-data -c 'php /var/www/html/occ maintenance:repair'

# Check for errors
docker exec nextcloud-nextcloud-1 \
  su -s /bin/bash www-data -c 'php /var/www/html/occ check'

# View PHP logs
docker logs nextcloud-nextcloud-1 | grep -i error
```

### DNS Issues

```bash
# Verify DNS records
dig drive.dobbertjeduik.nl
dig healthcheck.dobbertjeduik.nl

# Check Hetzner DNS zone in Terraform
cd terraform
terraform state show hcloud_zone.domain
```

## Cost Estimate

Monthly costs (excluding VAT):
- VPS (cpx32): ~€25/month
- Volume (50 GB): ~€3/month
- Object Storage (base): €4.99/month (includes 1 TB storage + 1 TB egress)
- DNS: Free

**Total**: ~€33/month

## Support

For issues or questions:
1. Check logs as described in Troubleshooting section
2. Review [Nextcloud documentation](https://docs.nextcloud.com)
3. Review [Restic documentation](https://restic.readthedocs.io)

## License

[Add your license information here]
