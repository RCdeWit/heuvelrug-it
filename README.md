# GL/PvdA Heuvelrug IT

Infrastructure-as-code (IaC) for GL/PvdA Heuvelrug's self-hosted Nextcloud instance. Uses Terraform for provisioning cloud resources on Hetzner and PyInfra for configuration management.

## Architecture

```text
┌───────────────────────────────────────────────────────────┐
│ Hetzner Cloud (Nuremberg - nbg1)                          │
│                                                           │
│  ┌─────────────────────────────────────────────────────┐  │
│  │ VPS (cpx32 - Ubuntu 24.04)                          │  │
│  │                                                     │  │
│  │  ┌─────────────┐      ┌──────────────────────────┐  │  │
│  │  │   Caddy     │─────▶│  Nextcloud (Docker)      │  │  │
│  │  │  (HTTPS)    │      │  - Web Application       │  │  │
│  │  └─────────────┘      │  - PostgreSQL Database   │  │  │
│  │                       │  - Redis Cache           │  │  │
│  │                       └──────────────────────────┘  │  │
│  │                                                     │  │
│  │  ┌──────────────────────────────────────────────┐   │  │
│  │  │  Backup Service (Docker)                     │   │  │
│  │  │  - Restic backups (daily 2 AM)               │   │  │
│  │  │  - Database dumps                            │   │  │
│  │  │  - Encrypted, deduplicated                   │   │  │
│  │  └──────────────────────────────────────────────┘   │  │
│  │                                                     │  │
│  │  ┌──────────────────────────────────────────────┐   │  │
│  │  │  Attached Volume (50 GB)                     │   │  │
│  │  │  - Nextcloud user data                       │   │  │
│  │  │  - PostgreSQL database files                 │   │  │
│  │  │  - Application files                         │   │  │
│  │  └──────────────────────────────────────────────┘   │  │
│  └─────────────────────────────────────────────────────┘  │
│                                                           │
│  ┌─────────────────────────────────────────────────────┐  │
│  │ Object Storage (S3-compatible)                      │  │
│  │  - Terraform state (heuvelrugterraformstate)        │  │
│  │  - Nextcloud backups (nextcloud-backups)            │  │
│  └─────────────────────────────────────────────────────┘  │
│                                                           │
│  ┌─────────────────────────────────────────────────────┐  │
│  │ DNS (dobbertjeduik.nl)                              │  │
│  │  - drive.dobbertjeduik.nl → VPS                     │  │
│  │  - healthcheck.dobbertjeduik.nl → VPS               │  │
│  └─────────────────────────────────────────────────────┘  │
└───────────────────────────────────────────────────────────┘
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
- S3 access keys for Object Storage (used for both Terraform state and Restic backups)
- SSH public key
- Generate passwords for PostgreSQL, Redis, Nextcloud, and Restic
- SMTP credentials for email notifications (see Email Configuration below)

**Note**: The S3 bucket name for backups is automatically retrieved from Terraform outputs during deployment. The PyInfra script will construct the S3 endpoint from your configured region (`TF_VAR_hetzner_region`).

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

### 5. Configure Email (Brevo)

Nextcloud requires SMTP configuration to send email notifications (user creation, password resets, etc.).

**Recommended**: Use [Brevo](https://www.brevo.com/) (EU-based, free tier: 300 emails/day)

1. Sign up at [https://www.brevo.com/](https://www.brevo.com/)
2. Navigate to: **SMTP & API** → **SMTP**
3. Click **Create a new SMTP key**
4. Copy the generated SMTP credentials
5. Add to your `.env` file:

```bash
export SMTP_HOST=smtp-relay.brevo.com
export SMTP_PORT=587
export SMTP_SECURE=tls
export SMTP_AUTHTYPE=LOGIN
export SMTP_NAME=your-brevo-email@example.com
export SMTP_PASSWORD=your-generated-smtp-key
export MAIL_FROM_ADDRESS=noreply
```

**Notes**:
- Use `SMTP_NAME` for the username (not `SMTP_USERNAME`) - this is the official Nextcloud Docker variable name
- The SMTP password is the API key from Brevo, not your account password
- The email domain is automatically taken from `TF_VAR_domain` (e.g., noreply@dobbertjeduik.nl)

**Alternative providers**:
- Mailgun EU (good Terraform support)
- Amazon SES (cheapest, requires AWS account)
- Postmark (excellent deliverability)

See `.env.example` for detailed configuration instructions.

#### Optional: Verify Domain for Better Deliverability

For production use, verify your domain with Brevo to improve email deliverability:

1. In Brevo, go to **Settings** → **Senders & IP** → **Add Domain**
2. Enter `dobbertjeduik.nl` and follow the verification steps
3. Brevo will provide DNS records including:
   - A verification code (code-verification TXT record)
   - 2 DKIM CNAME records (mail._domainkey, mail2._domainkey)
4. Add these to your `.env` file:

```bash
export TF_VAR_brevo_verification_code="your-verification-code-here"
export TF_VAR_brevo_dkim_key1="b1.your-domain-com.dkim.brevo.com"
export TF_VAR_brevo_dkim_key2="b2.your-domain-com.dkim.brevo.com"
```

5. Run Terraform to add the DNS records:

```bash
cd terraform
terraform apply
```

The SPF and DMARC records are automatically configured. Once DNS propagates (5-15 minutes), verify the domain in Brevo.

**Note**: Emails will work without domain verification, but may have lower deliverability and show "sent via brevo.com" warnings.

### 6. Configure VPS

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

### 7. Verify Deployment

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

#### Quick Start: Automated Restore Utility

The easiest way to restore backups is using the automated restore utility. Run it locally and it will connect to your VPS via SSH:

```bash
# Run the restore utility (from your local machine)
./restore.sh <vps-hostname-or-ip>

# Example
./restore.sh drive.dobbertjeduik.nl
```

The utility provides an interactive menu with the following options:

1. **Full restore** - Complete disaster recovery (destructive)
2. **Restore to temporary location** - Inspect backup contents safely
3. **Restore specific files/directories** - Selective restoration
4. **Database only** - Restore PostgreSQL database only
5. **Exit**

**Features:**
- Runs locally - no need to copy files to VPS
- Automatically loads credentials from the VPS environment file via SSH
- Lists available snapshots with timestamps
- Manages maintenance mode and service orchestration remotely
- Validates destructive operations with confirmation prompts
- Provides clear progress indicators and colored output
- Handles all the complexity of the manual restore process

**Requirements:**
- SSH key authentication configured for the `deploy` user
- Script runs from your local machine and connects to VPS

#### Manual Restore (Advanced)

##### 1. List Available Snapshots

```bash
# SSH into VPS or backup container
docker exec -it nextcloud-backup-1 /bin/sh

# List all snapshots
restic snapshots

# List snapshots with specific tags
restic snapshots --tag nextcloud
```

##### 2. Restore Files

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

##### 3. Restore to Production

**⚠️ Warning**: This will overwrite your production data. Always test with a temporary restore first!

**Note**: The backup container has read-only access to data directories for safety. To restore to production, you must run restic from the VPS host (not from inside the container).

```bash
# 1. Enable maintenance mode
sudo docker exec nextcloud-nextcloud-1 \
  su -s /bin/bash www-data -c 'php /var/www/html/occ maintenance:mode --on'

# 2. Stop services (all of them, including backup container)
cd /opt/nextcloud
sudo docker compose down

# 3. Set environment variables for restic
# The .env file is owned by root, so extract values with sudo
export RESTIC_PASSWORD=$(sudo grep '^RESTIC_PASSWORD=' /opt/nextcloud/.env | cut -d= -f2-)
export AWS_ACCESS_KEY_ID=$(sudo grep '^AWS_ACCESS_KEY_ID=' /opt/nextcloud/.env | cut -d= -f2-)
export AWS_SECRET_ACCESS_KEY=$(sudo grep '^AWS_SECRET_ACCESS_KEY=' /opt/nextcloud/.env | cut -d= -f2-)
export AWS_S3_ENDPOINT=$(sudo grep '^AWS_S3_ENDPOINT=' /opt/nextcloud/.env | cut -d= -f2-)
export AWS_S3_BUCKET=$(sudo grep '^AWS_S3_BUCKET=' /opt/nextcloud/.env | cut -d= -f2-)
export RESTIC_REPOSITORY="s3:${AWS_S3_ENDPOINT}/${AWS_S3_BUCKET}"

# 4. Find the mount point
MOUNT_POINT=$(sudo findmnt -n -o TARGET /dev/disk/by-id/scsi-0HC_Volume_* | grep -v '/var/lib/docker')

# 5. List snapshots and choose one to restore
restic snapshots --tag nextcloud
# Note the snapshot ID from the output (e.g., "a1b2c3d4")

# 6. Restore data directly to the mount point
# NOTE: Restic restore is ADDITIVE - it doesn't delete extra files
# For a clean restore (exact snapshot state), clear directories first:
sudo rm -rf ${MOUNT_POINT}/nextcloud_db/*
sudo rm -rf ${MOUNT_POINT}/nextcloud_data/*
sudo rm -rf ${MOUNT_POINT}/ncdata/*

# Now restore
sudo -E restic restore <snapshot-id> --target ${MOUNT_POINT}

# This restores to the mount point structure:
# - ${MOUNT_POINT}/nextcloud_db → PostgreSQL data
# - ${MOUNT_POINT}/nextcloud_data → Nextcloud app data
# - ${MOUNT_POINT}/ncdata → User files

# 7. Start all services
cd /opt/nextcloud
sudo docker compose up -d

# 8. Disable maintenance mode and repair
sudo docker exec nextcloud-nextcloud-1 \
  su -s /bin/bash www-data -c 'php /var/www/html/occ maintenance:mode --off'
sudo docker exec nextcloud-nextcloud-1 \
  su -s /bin/bash www-data -c 'php /var/www/html/occ maintenance:repair'
```

##### 4. Restore Specific Files Only

If you only need to restore specific files (e.g., accidentally deleted user files):

```bash
# Restore to temp location first
docker exec nextcloud-backup-1 restic restore <snapshot-id> \
  --target /tmp/restore \
  --include /mnt/data/ncdata/username/files/important-file.pdf

# Copy to production (from VPS)
cp /tmp/restore/mnt/data/ncdata/username/files/important-file.pdf \
   ${MOUNT_POINT}/ncdata/username/files/

# Fix permissions
chown -R www-data:www-data ${MOUNT_POINT}/ncdata/username/files/

# Trigger Nextcloud file scan
docker exec nextcloud-nextcloud-1 \
  su -s /bin/bash www-data -c 'php /var/www/html/occ files:scan username'
```

##### 5. Complete Disaster Recovery

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
# Restic is already installed by PyInfra

# Configure environment (extract from root-owned .env file)
export RESTIC_PASSWORD=$(sudo grep '^RESTIC_PASSWORD=' /opt/nextcloud/.env | cut -d= -f2-)
export AWS_ACCESS_KEY_ID=$(sudo grep '^AWS_ACCESS_KEY_ID=' /opt/nextcloud/.env | cut -d= -f2-)
export AWS_SECRET_ACCESS_KEY=$(sudo grep '^AWS_SECRET_ACCESS_KEY=' /opt/nextcloud/.env | cut -d= -f2-)
export AWS_S3_ENDPOINT=$(sudo grep '^AWS_S3_ENDPOINT=' /opt/nextcloud/.env | cut -d= -f2-)
export AWS_S3_BUCKET=$(sudo grep '^AWS_S3_BUCKET=' /opt/nextcloud/.env | cut -d= -f2-)
export RESTIC_REPOSITORY="s3:${AWS_S3_ENDPOINT}/${AWS_S3_BUCKET}"

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

### Managing Backups

The backup container runs automated daily backups at 2 AM using Restic. To manually interact with backups:

```bash
# View backup snapshots (RESTIC_REPOSITORY is pre-configured)
docker exec nextcloud-backup-1 restic snapshots --tag nextcloud

# View repository statistics
docker exec nextcloud-backup-1 restic stats --mode restore-size

# List all snapshots with details
docker exec nextcloud-backup-1 restic snapshots

# Manually trigger a backup
docker exec nextcloud-backup-1 /bin/sh /backup.sh

# Check backup logs
docker logs nextcloud-backup-1

# Interactive shell (for more complex operations)
docker exec -it nextcloud-backup-1 /bin/sh
# Inside the container, restic commands work directly:
# restic snapshots
# restic check
# restic restore <snapshot-id> --target /restore
```

The backup script (`vps/nextcloud/backup.sh`) automatically:
- Enables Nextcloud maintenance mode
- Creates PostgreSQL database dump
- Backs up database, Nextcloud files, and user data
- Disables maintenance mode
- Prunes old backups based on retention policy (30 days daily, 52 weeks weekly, 24 months monthly)
- Runs integrity checks weekly on Sundays

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
├── restore.sh          # Automated backup restoration utility
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

### Email Not Sending

```bash
# Check SMTP configuration
docker exec nextcloud-nextcloud-1 \
  su -s /bin/bash www-data -c 'php /var/www/html/occ config:list system' | grep mail

# Test email sending (sends test email to admin)
docker exec nextcloud-nextcloud-1 \
  su -s /bin/bash www-data -c 'php /var/www/html/occ config:system:set mail_domain --value="your-domain.com"'

# View email-related errors in logs
docker exec nextcloud-nextcloud-1 cat /var/www/html/data/nextcloud.log | grep -i "mail\|smtp"
```

**Common issues**:
- Incorrect SMTP credentials → Check Brevo dashboard for correct API key
- Firewall blocking port 587 → Test with `telnet smtp-relay.brevo.com 587`
- Wrong sender domain → Ensure `MAIL_DOMAIN` matches your domain

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
