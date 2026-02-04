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
│  │  │  Komodo Periphery (Docker)                   │   │  │
│  │  │  - Container monitoring agent                │   │  │
│  │  │  - Bound to Tailscale IP only (port 8120)    │   │  │
│  │  └──────────────────────────────────────────────┘   │  │
│  │                                                     │  │
│  │  ┌──────────────────────────────────────────────┐   │  │
│  │  │  Tailscale (tag:vps-external)                │   │  │
│  │  │  - Mesh VPN for private networking           │   │  │
│  │  │  - Allows Komodo Core access from NAS        │   │  │
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
- **ClamAV**: Antivirus daemon for file scanning
- **Restic**: Encrypted, deduplicated backups to Object Storage

### Monitoring & Networking
- **Tailscale**: Mesh VPN for secure private networking (`tag:vps-external`)
- **Komodo Periphery**: Docker container monitoring agent (bound to Tailscale IP only)

### Nextcloud Apps

Apps are managed automatically via the custom entrypoint script (`vps/nextcloud/nextcloud-entrypoint.sh`).

**Installed apps:**

| App | Description |
|-----|-------------|
| `richdocuments` | Nextcloud Office - document editing via Collabora |
| `spreed` | Nextcloud Talk - video conferencing and chat |
| `notify_push` | Client Push - real-time sync for desktop/mobile clients |
| `admin_audit` | Audit logging - tracks user actions for compliance |
| `files_antivirus` | Antivirus scanning - scans uploads via ClamAV daemon |

**Disabled apps:**

| App | Reason |
|-----|--------|
| `app_api` | External app hosting platform - not used |
| `photos` | Photo gallery - not needed for file storage focus |

**Available but not installed:**

These apps can be enabled via Admin Settings → Apps:

| App | Description |
|-----|-------------|
| `files_accesscontrol` | Automated file handling rules |
| `twofactor_totp` | Two-factor authentication (TOTP) |
| `bruteforcesettings` | Brute-force protection settings UI |
| `suspicious_login` | Suspicious login detection |
| `files_retention` | Automatic file retention policies |
| `quota_warning` | Warn users when approaching storage quota |
| `groupfolders` | Shared folders with group permissions |
| `deck` | Kanban-style project management |
| `calendar` | CalDAV calendar |
| `contacts` | CardDAV contacts |
| `mail` | Email client |
| `notes` | Note-taking app |
| `tasks` | Task management (integrates with calendar) |
| `bookmarks` | Bookmark manager |

**Managing apps via command line:**

```bash
# List installed apps
docker exec nextcloud-nextcloud-1 su -s /bin/bash www-data -c \
  'php /var/www/html/occ app:list'

# Install and enable an app
docker exec nextcloud-nextcloud-1 su -s /bin/bash www-data -c \
  'php /var/www/html/occ app:install <app-id>'
docker exec nextcloud-nextcloud-1 su -s /bin/bash www-data -c \
  'php /var/www/html/occ app:enable <app-id>'

# Disable an app
docker exec nextcloud-nextcloud-1 su -s /bin/bash www-data -c \
  'php /var/www/html/occ app:disable <app-id>'
```

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

**Verify DNS propagation before continuing:**

```bash
# Check if Hetzner nameservers are responding
dig NS dobbertjeduik.nl +short

# Should show:
# helium.ns.hetzner.de.
# hydrogen.ns.hetzner.com.
# oxygen.ns.hetzner.com.
```

If nameservers don't match, wait and try again. Propagation typically takes 1-6 hours but can take up to 48 hours.

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

#### Understanding Terraform State Migration

**If this is your first deployment:**
- Terraform will create local state first
- `-migrate-state` will offer to move it to S3
- Answer "yes" to migrate

**If you already have remote state in S3:**
- Terraform will use the remote state automatically
- `-migrate-state` is a no-op (safe to run)

**If you have local state from a previous deployment:**
- `-migrate-state` will detect existing local state
- It will prompt to migrate to S3
- Answer "yes" and local state will be uploaded securely

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
- The email domain is automatically taken from `TF_VAR_domain` (e.g., `noreply@dobbertjeduik.nl`)

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

### Automated Backup Monitoring

This deployment includes optional integration with healthcheck monitoring services. When configured, the backup script automatically pings a monitoring URL after each successful backup.

**Setup with Healthchecks.io (Recommended):**

1. Sign up at [https://healthchecks.io](https://healthchecks.io) (free tier available)
2. Create a new check with:
   - **Period**: 1 day (backups run daily at 2 AM)
   - **Grace time**: 2 hours (buffer for backup duration)
3. Copy your unique ping URL
4. Add to your `.env` file:
   ```bash
   export HEALTHCHECK_URL=https://hc-ping.com/your-unique-uuid
   ```
5. Redeploy to apply: `uv run pyinfra/configure_vps.py`

**How it works:**
- After each successful backup, the script pings your monitoring URL
- If no ping is received within 26 hours (24h + 2h grace), you'll receive an alert
- Alerts can be sent via email, SMS, Slack, Discord, etc.

**Alternative services:**
- [UptimeRobot](https://uptimerobot.com/) - HTTP(S) monitoring
- [Better Uptime](https://betteruptime.com/) - Incident management

### Manual Backup Monitoring

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

### Container Monitoring with Komodo

This deployment includes optional integration with [Komodo](https://komo.do/) for Docker container monitoring and management via Tailscale mesh VPN.

**Architecture:**
- **Komodo Core**: Runs on your NAS or management server
- **Komodo Periphery**: Agent running on this VPS, accessible only via Tailscale
- **Tailscale**: Provides secure private networking between Core and Periphery

**Setup:**

1. Add to your `.env` file:
   ```bash
   export TAILSCALE_AUTH_KEY=tskey-auth-xxxxx  # From Tailscale admin console
   export PERIPHERY_PASSKEY=your-passkey       # Shared secret for Komodo auth
   ```

2. Deploy Tailscale and Periphery:
   ```bash
   uv run pyinfra/configure_vps.py --stage 1-system  # Installs Tailscale
   uv run pyinfra/configure_vps.py --stage 2-docker  # Deploys Periphery container
   ```

3. Find the VPS Tailscale address:
   ```bash
   ssh deploy@<vps-ip> "tailscale status"
   # Note the IP (100.x.x.x) or hostname
   ```

4. Register in Komodo Core:
   - Add a new server with address: `<tailscale-ip>:8120` or `<tailscale-hostname>:8120`
   - Use the same passkey configured in `PERIPHERY_PASSKEY`

**Security notes:**
- Periphery is bound to the Tailscale IP only (not exposed to the internet)
- Tailscale ACLs should restrict access to port 8120 from your management server only
- The `komodo.skip: "true"` label prevents Periphery from managing itself

**Without Komodo:**

If you don't use Komodo, simply omit `TAILSCALE_AUTH_KEY` and `PERIPHERY_PASSKEY` from your `.env`. Tailscale won't join the tailnet and Periphery won't start (it falls back to binding to 127.0.0.1).

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
./restore.sh <vps-ip-address>

# Example (use IP address, not hostname)
./restore.sh 123.45.67.89
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

**Estimated total time: 45-90 minutes** (depending on backup size and network speed)

For complete infrastructure loss:

```bash
# 1. Provision fresh infrastructure (~10 minutes)
source .env
cd terraform
terraform apply

# 2. Deploy base configuration (~15 minutes)
cd ..
uv run pyinfra/configure_vps.py --fresh

# 3. Stop Nextcloud services (~1 minute)
ssh deploy@<vps-ip>
cd /opt/nextcloud
docker compose down

# 4. Restore data from backup (~20-60 minutes depending on data size)
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
│   │   ├── 0-bootstrap.py  # Creates deploy user, SSH setup
│   │   ├── 1-system.py     # System packages, firewall, Tailscale
│   │   ├── 2-docker.py     # Docker, Nextcloud stack, Komodo Periphery
│   │   └── 3-caddy.py      # Reverse proxy configuration
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

### Collabora Office Not Working

```bash
# Check Collabora logs
docker logs nextcloud-collabora-1

# Verify Nextcloud can reach Collabora
docker exec nextcloud-nextcloud-1 curl -I http://collabora:9980

# Check Collabora configuration in Nextcloud
docker exec nextcloud-nextcloud-1 su -s /bin/bash www-data -c \
  'php /var/www/html/occ config:app:get richdocuments wopi_url'
# Should return: https://office.dobbertjeduik.nl

# Test document editing
# 1. Log into Nextcloud web interface
# 2. Create a new document (+ → New Document)
# 3. Should open in-browser editor
```

## Nextcloud OCC Command Reference

Nextcloud's `occ` (ownCloud Console) is a powerful command-line tool for administration.

**General syntax:**
```bash
docker exec nextcloud-nextcloud-1 su -s /bin/bash www-data -c 'php /var/www/html/occ <command>'
```

**Useful commands:**

```bash
# List all available commands
docker exec nextcloud-nextcloud-1 su -s /bin/bash www-data -c 'php /var/www/html/occ list'

# Get help for a specific command
docker exec nextcloud-nextcloud-1 su -s /bin/bash www-data -c 'php /var/www/html/occ help files:scan'

# Maintenance mode
docker exec nextcloud-nextcloud-1 su -s /bin/bash www-data -c 'php /var/www/html/occ maintenance:mode --on'
docker exec nextcloud-nextcloud-1 su -s /bin/bash www-data -c 'php /var/www/html/occ maintenance:mode --off'

# File operations
docker exec nextcloud-nextcloud-1 su -s /bin/bash www-data -c 'php /var/www/html/occ files:scan --all'
docker exec nextcloud-nextcloud-1 su -s /bin/bash www-data -c 'php /var/www/html/occ files:scan username'

# System maintenance
docker exec nextcloud-nextcloud-1 su -s /bin/bash www-data -c 'php /var/www/html/occ maintenance:repair'
docker exec nextcloud-nextcloud-1 su -s /bin/bash www-data -c 'php /var/www/html/occ check'

# Database operations
docker exec nextcloud-nextcloud-1 su -s /bin/bash www-data -c 'php /var/www/html/occ db:add-missing-indices'
docker exec nextcloud-nextcloud-1 su -s /bin/bash www-data -c 'php /var/www/html/occ db:add-missing-columns'

# Configuration
docker exec nextcloud-nextcloud-1 su -s /bin/bash www-data -c 'php /var/www/html/occ config:list'
docker exec nextcloud-nextcloud-1 su -s /bin/bash www-data -c 'php /var/www/html/occ config:system:get version'
```

## Upgrading Nextcloud

### Minor Version Updates (e.g., 30.0.1 → 30.0.2)

Minor updates are straightforward and safe:

```bash
ssh deploy@<vps-ip>
cd /opt/nextcloud
sudo docker compose pull nextcloud
sudo docker compose up -d nextcloud

# Verify upgrade
docker exec nextcloud-nextcloud-1 su -s /bin/bash www-data -c 'php /var/www/html/occ status'
```

### Major Version Updates (e.g., 30 → 31)

Major version updates require careful planning:

**Before upgrading:**

1. **Read release notes** at https://nextcloud.com/changelog/
2. **Check app compatibility** - some apps may not support the new version yet
3. **Backup before upgrade**:
   ```bash
   ssh deploy@<vps-ip>
   docker exec nextcloud-backup-1 /bin/sh /backup.sh
   ```

**Perform upgrade:**

1. Update Docker image tag in `vps/docker/nextcloud.yml.j2`:
   ```yaml
   image: nextcloud:31  # Change from nextcloud:30
   ```

2. Deploy the update:
   ```bash
   uv run pyinfra/configure_vps.py
   ```

3. Run maintenance commands:
   ```bash
   ssh deploy@<vps-ip>
   docker exec nextcloud-nextcloud-1 su -s /bin/bash www-data -c \
     'php /var/www/html/occ maintenance:repair'
   docker exec nextcloud-nextcloud-1 su -s /bin/bash www-data -c \
     'php /var/www/html/occ db:add-missing-indices'
   docker exec nextcloud-nextcloud-1 su -s /bin/bash www-data -c \
     'php /var/www/html/occ check'
   ```

4. Test functionality:
   - Log into web interface
   - Test file upload/download
   - Test document editing (Collabora)
   - Check admin overview for warnings

**Rollback procedure (if needed):**

If the upgrade fails, restore from backup following the [Disaster Recovery](#disaster-recovery) procedures.

## User Management

### Adding Users

**Via Web UI:**
1. Log in as admin
2. Top-right menu → Users
3. Click "+ New user"
4. Fill in username, display name, email, and password
5. Assign to groups if needed

**Via Command Line:**
```bash
# Add user (will prompt for password)
docker exec nextcloud-nextcloud-1 su -s /bin/bash www-data -c \
  'php /var/www/html/occ user:add username'

# Add user with options
docker exec nextcloud-nextcloud-1 su -s /bin/bash www-data -c \
  'php /var/www/html/occ user:add --display-name="John Doe" --group=users username'
```

### Resetting Passwords

```bash
# Reset user password (will prompt for new password)
docker exec nextcloud-nextcloud-1 su -s /bin/bash www-data -c \
  'php /var/www/html/occ user:resetpassword username'
```

### Managing Quotas

```bash
# Set user quota to 10GB
docker exec nextcloud-nextcloud-1 su -s /bin/bash www-data -c \
  'php /var/www/html/occ user:setting username files quota "10 GB"'

# Set unlimited quota
docker exec nextcloud-nextcloud-1 su -s /bin/bash www-data -c \
  'php /var/www/html/occ user:setting username files quota none'

# Check user quota usage
docker exec nextcloud-nextcloud-1 su -s /bin/bash www-data -c \
  'php /var/www/html/occ user:report'
```

### Disabling/Enabling Users

```bash
# Disable user (prevents login)
docker exec nextcloud-nextcloud-1 su -s /bin/bash www-data -c \
  'php /var/www/html/occ user:disable username'

# Enable user
docker exec nextcloud-nextcloud-1 su -s /bin/bash www-data -c \
  'php /var/www/html/occ user:enable username'

# Delete user (permanent!)
docker exec nextcloud-nextcloud-1 su -s /bin/bash www-data -c \
  'php /var/www/html/occ user:delete username'
```

## Scaling the Deployment

### Vertical Scaling (Upgrading Instance Size)

If your organization grows and needs more resources:

**1. Resize VPS in Terraform:**

Edit `terraform/hetzner.tf`:
```terraform
server_type = "cpx42"  # Change from cpx32 (16 vCPU, 32GB RAM)
```

**2. Update PostgreSQL tuning for new RAM:**

Edit `vps/docker/nextcloud.yml.j2`:
```yaml
-c shared_buffers=4GB              # Was 2GB
-c effective_cache_size=20GB       # Was 10GB
-c maintenance_work_mem=1GB        # Was 512MB
```

**3. Apply changes:**
```bash
cd terraform && terraform apply
# Hetzner will resize the instance (may cause 1-2 minutes downtime)

cd .. && uv run pyinfra/configure_vps.py
```

**Instance size recommendations:**
- **cpx22** (4 vCPU, 8GB): Up to 20 users, light usage (~€15/month)
- **cpx32** (8 vCPU, 16GB): Up to 50 users, moderate usage (~€25/month) - **Current**
- **cpx42** (16 vCPU, 32GB): Up to 100 users, heavy usage (~€48/month)
- **cpx52** (32 vCPU, 64GB): 100+ users, very heavy usage (~€96/month)

### Storage Expansion

To expand the 50GB data volume:

**1. Resize in Terraform:**

Edit `terraform/hetzner.tf`:
```terraform
resource "hcloud_volume" "volume1" {
  size = 100  # Change from 50 to 100GB
  # ...
}
```

**2. Apply changes:**
```bash
cd terraform
terraform apply  # Hetzner resizes the volume instantly
```

**3. Resize filesystem on VPS:**
```bash
ssh deploy@<vps-ip>
# Find the volume device
DEVICE=$(findmnt -n -o SOURCE /mnt/HC_Volume_* | head -1)
sudo resize2fs $DEVICE
df -h  # Verify new size
```

**Note:** Volume expansion is instant and non-disruptive. Volumes can be expanded but not shrunk.

### Monitoring Resource Usage

```bash
# Check CPU and memory usage
ssh deploy@<vps-ip> htop

# Check disk usage
ssh deploy@<vps-ip> df -h

# Check Docker resource usage
ssh deploy@<vps-ip> docker stats

# Check per-service resource usage
ssh deploy@<vps-ip> docker stats --no-stream --format \
  "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}"
```

## Cost Estimate

Monthly costs (excluding VAT):
- VPS (cpx32): ~€25/month
- Volume (50 GB): ~€3/month
- Object Storage (base): €4.99/month (includes 1 TB storage + 1 TB egress)
- DNS: Free

**Total**: ~€33/month

### Cost Optimization Tips

**Potential savings:**

1. **Downsize VPS** (if usage is low):
   - cpx22 (4 vCPU, 8GB RAM): ~€15/month (saves €10/month)
   - Suitable for <20 users with light usage
   - Test first: Monitor resource usage for 1-2 weeks before downsizing

2. **Reduce backup retention** (if 2+ years not needed):
   - Current: 30 daily + 52 weekly + 24 monthly
   - Alternative: 14 daily + 8 weekly + 12 monthly
   - Reduces S3 storage by ~40%
   - Edit `BACKUP_RETENTION_DAYS` in `.env` and backup script retention policy

3. **Use cheaper region** (if latency acceptable):
   - Falkenstein (fsn1) may have slightly lower costs
   - Check current pricing: https://www.hetzner.com/cloud#pricing
   - Consider proximity to users (Germany-based users benefit from nbg1)

**Current setup is already cost-optimized for:**
- Small-to-medium organizations (up to 50 users)
- Reliable infrastructure with proven scaling path
- Professional-grade backups and disaster recovery

## Security Considerations

### Security Features

- All services run behind Caddy with automatic HTTPS
- Backups are encrypted with Restic before upload
- S3 buckets have `prevent_destroy` lifecycle rule
- Object Storage versioning enabled for backup bucket
- Passwords generated with `openssl rand -base64 32`
- SSH key-based authentication only (no password auth)
- PostgreSQL and Redis not exposed externally
- UFW firewall configured (only SSH, HTTP, HTTPS exposed)
- Docker health checks monitor service availability
- Redis persistence with AOF for data durability
- Tailscale mesh VPN for secure private networking (monitoring access)
- Komodo Periphery bound to Tailscale IP only (not internet-accessible)

### Security Maintenance

**Monthly tasks:**
- Update Nextcloud: `docker compose pull && docker compose up -d`
- Update system: `ssh deploy@vps "sudo apt update && sudo apt upgrade -y"`
- Review access logs: `docker logs nextcloud-nextcloud-1 | grep -E "ERROR|WARN"`
- Check Nextcloud admin overview for security warnings

**Recommendations:**
- Subscribe to [Nextcloud security advisories](https://nextcloud.com/security/advisories/)
- Monitor [Hetzner status page](https://status.hetzner.com/)
- Review backup health weekly via Healthchecks.io
- Consider adding fail2ban for SSH brute-force protection (optional)

### Attack Surface

**Exposed services:**
- Port 22 (SSH) - Key authentication only, no passwords
- Port 80/443 (HTTP/HTTPS) - Behind Caddy reverse proxy with automatic HTTPS

**Not exposed (internal only):**
- PostgreSQL (5432) - Internal Docker network only
- Redis (6379) - Internal Docker network only
- Nextcloud app (8080) - Localhost only, proxied by Caddy
- Collabora (9980) - Localhost only, proxied by Caddy
- Komodo Periphery (8120) - Tailscale IP only, not exposed to internet

**Security best practices implemented:**
- Least privilege access (deploy user with sudo, not root)
- Encrypted backups at rest and in transit
- Regular automated backups with off-site storage
- Infrastructure as Code (no manual configuration drift)
- HSTS headers enforced for all HTTPS traffic
- DNS CAA records restrict certificate issuance to Let's Encrypt

## Support

For issues or questions:
1. Check logs as described in Troubleshooting section
2. Review [Nextcloud documentation](https://docs.nextcloud.com)
3. Review [Restic documentation](https://restic.readthedocs.io)

## License

Apache License 2.0 - See [LICENSE](LICENSE) for details.

This project includes configurations for third-party software:
- **Nextcloud** - [AGPL-3.0](https://github.com/nextcloud/server/blob/master/COPYING)
- **PostgreSQL** - [PostgreSQL License](https://www.postgresql.org/about/licence/)
- **Redis** - [BSD-3-Clause](https://redis.io/docs/about/license/)
- **Caddy** - [Apache-2.0](https://github.com/caddyserver/caddy/blob/master/LICENSE)
- **Collabora Online** - [MPL-2.0](https://www.collaboraoffice.com/code/)
- **Restic** - [BSD-2-Clause](https://github.com/restic/restic/blob/master/LICENSE)
