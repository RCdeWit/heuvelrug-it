# PRO Heuvelrug IT

Infrastructure-as-code (IaC) for PRO Heuvelrug's self-hosted Nextcloud instance. Uses Terraform for provisioning cloud resources on Hetzner and PyInfra for configuration management.

> [!NOTE]
> This repository is provided as-is. Documentation is maintained on a best-effort basis. If you'd prefer a fully managed deployment, reach out to [rob@binary3.dev](mailto:rob@binary3.dev). I'm happy to provide this to PRO members at a steep discount. 💚❤️

## Architecture

```text
┌──────────────────────────────────────────────────────────────────┐
│ Hetzner Cloud (Nuremberg - nbg1)                                 │
│                                                                  │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │ VPS (cpx42 - Ubuntu 24.04)                                 │  │
│  │                                                            │  │
│  │  ┌──────────┐   ┌─────────────────────────────────────┐    │  │
│  │  │  Caddy   │──▶│  Nextcloud                          │    │  │
│  │  │ (HTTPS)  │   │  - PostgreSQL 15  (database)        │    │  │
│  │  └──────────┘   │  - Redis 7        (cache/locking)   │    │  │
│  │       │         └─────────────────────────────────────┘    │  │
│  │       ├────────▶ Collabora Online   (document editing)     │  │
│  │       ├────────▶ Whiteboard         (collaborative drawing)│  │
│  │       └────────▶ Signaling          (Talk HPB)             │  │
│  │                                                            │  │
│  │  ┌─────────────────────────────────────────────────────┐   │  │
│  │  │  Talk Stack                                         │   │  │
│  │  │  - coturn     (TURN relay, UDP 3478 + 49152–65535)  │   │  │
│  │  │  - NATS       (message broker)                      │   │  │
│  │  │  - signaling  (High Performance Backend)            │   │  │
│  │  │  - Janus      (WebRTC gateway)                      │   │  │
│  │  └─────────────────────────────────────────────────────┘   │  │
│  │                                                            │  │
│  │  ┌─────────────────────────────────────────────────────┐   │  │
│  │  │  Backup Service                                     │   │  │
│  │  │  - Restic (daily 2 AM, encrypted + deduplicated)    │   │  │
│  │  │  - PostgreSQL dump + Nextcloud data                 │   │  │
│  │  └─────────────────────────────────────────────────────┘   │  │
│  │                                                            │  │
│  │  ┌─────────────────────────────────────────────────────┐   │  │
│  │  │  Komodo Periphery  (port 8120, Tailscale only)      │   │  │
│  │  └─────────────────────────────────────────────────────┘   │  │
│  │                                                            │  │
│  │  ┌─────────────────────────────────────────────────────┐   │  │
│  │  │  Tailscale  (tag:vps-external)                      │   │  │
│  │  │  - Only SSH access path (public SSH blocked)        │  │  │
│  │  └─────────────────────────────────────────────────────┘  │  │
│  │                                                           │  │
│  │  ┌─────────────────────────────────────────────────────┐  │  │
│  │  │  Attached Volume (50 GB)                            │  │  │
│  │  │  - Nextcloud user data + PostgreSQL files           │  │  │
│  │  └─────────────────────────────────────────────────────┘  │  │
│  └───────────────────────────────────────────────────────────┘  │
│                                                                 │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │ Object Storage (S3-compatible)                            │  │
│  │  - Terraform state  (manually pre-created bucket)         │  │
│  │  - Nextcloud backups (bucket managed by Terraform)        │  │
│  └───────────────────────────────────────────────────────────┘  │
│                                                                 │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │ DNS (proheuvelrug.nl)                                     │  │
│  │  - drive.proheuvelrug.nl      → VPS (Nextcloud)           │  │
│  │  - office.proheuvelrug.nl     → VPS (Collabora)           │  │
│  │  - whiteboard.proheuvelrug.nl → VPS (Whiteboard)          │  │
│  │  - signaling.proheuvelrug.nl  → VPS (Talk HPB)            │  │
│  │  - turn.proheuvelrug.nl       → VPS (TURN)                │  │
│  └───────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

## Components

### Infrastructure
- **Hetzner Cloud VPS**: cpx42 (8 vCPU, 32 GB RAM), Ubuntu 24.04, Nuremberg
- **Hetzner Volume**: 50 GB persistent storage attached to VPS
- **Hetzner Object Storage**: S3-compatible storage for backups and Terraform state
- **Hetzner DNS**: Managed DNS for the domain

### Application Stack
- **Caddy**: Reverse proxy with automatic HTTPS via Let's Encrypt (Hetzner DNS challenge)
- **Nextcloud**: Self-hosted file sync and collaboration platform
  - **PostgreSQL 15**: Database backend
  - **Redis 7**: Caching and file locking
- **Collabora Online**: In-browser document editing (Writer, Calc, Impress)
- **Whiteboard**: Real-time collaborative drawing
- **ClamAV**: Antivirus daemon for file scanning
- **Restic**: Encrypted, deduplicated backups to Object Storage

### Networking & Security
- **Hetzner Firewall**: Only HTTP/HTTPS/ICMP/TURN exposed; SSH blocked from public internet
- **Tailscale**: Mesh VPN providing the only SSH access path (`tag:vps-external`)
- **Komodo Periphery**: Docker container monitoring agent, bound to Tailscale IP only

### Nextcloud Apps

Apps are managed declaratively via `vps/nextcloud/nextcloud-entrypoint.sh`, which runs on container startup and installs/configures apps automatically using `occ`. No manual app installation is required.

**Installed and configured automatically:**

| App | Description |
|-----|-------------|
| `richdocuments` | Nextcloud Office — document editing via Collabora |
| `spreed` | Nextcloud Talk — video conferencing, chat, and TURN/HPB integration |
| `whiteboard` | Collaborative whiteboard |
| `notify_push` | Client Push — real-time sync for desktop and mobile clients |
| `admin_audit` | Audit logging — tracks user actions for compliance |
| `files_antivirus` | Antivirus scanning — scans uploads via ClamAV daemon |

**Disabled automatically:**

| App       | Reason                                            |
|-----------|---------------------------------------------------|
| `app_api` | External app hosting platform — not used          |
| `photos`  | Photo gallery — not needed for file storage focus |

To add an app to the declarative setup, add the appropriate `occ app:install` and `occ app:enable` calls to `nextcloud-entrypoint.sh`. Other apps (e.g. `calendar`, `contacts`, `deck`) can also be enabled ad hoc via **Admin Settings → Apps**.

### Backup Strategy
- **Frequency**: Daily at 2 AM (during Nextcloud maintenance window)
- **Retention**: 30 daily · 52 weekly · 24 monthly
- **Method**: Incremental, encrypted, deduplicated via Restic
- **Storage**: Hetzner Object Storage (S3-compatible)
- **What's backed up**: PostgreSQL database dump + Nextcloud user data + application config

---

## Setup

### Prerequisites

**Accounts required:**
- [Hetzner Cloud](https://www.hetzner.com/cloud) — with API token and Object Storage access keys
- [Tailscale](https://tailscale.com) — required for SSH access (see [Tailscale Setup](#2-tailscale-setup) below)
- [Brevo](https://www.brevo.com) — for outgoing email (free tier: 300 emails/day)

**Local tools:**
- Terraform 1.9.5+
- Python 3.12+ with `uv`
- SSH key pair for deployment

### 1. Clone and Configure

Clone the repository:

```bash
git clone <repository-url>
cd heuvelrug-it
```

#### Option A: 1Password (recommended)

If you use 1Password, secrets are stored in the vault `Infra` under `GitHub.RCdeWit.heuvelrug-it`. The `.env.1password` template uses `op://` references that are resolved at runtime:

```bash
op inject -i .env.1password -o .env
source .env
```

Re-run `op inject` any time you update secrets in 1Password.

#### Option B: Manual configuration

```bash
cp .env.example .env
```

Edit `.env` and fill in all required values. See `.env.example` for full documentation of every variable.

### 2. Tailscale Setup

Tailscale is **required** — public SSH (port 22) is blocked at the Hetzner firewall level. All SSH access goes through Tailscale, which provides encrypted mesh VPN connectivity without exposing SSH to the internet.

1. [Sign up for Tailscale](https://tailscale.com) and create a tailnet
2. In the Tailscale admin panel, go to **Settings → Keys**
3. Create an **auth key** with:
   - **Reusable**: yes (needed for reprovisioning)
   - **Tags**: `tag:vps-external`
4. Add the key to `.env`:
   ```bash
   export TF_VAR_tailscale_auth_key=tskey-auth-...
   export TAILSCALE_AUTH_KEY=tskey-auth-...
   ```

The VPS joins your tailnet automatically during cloud-init provisioning — before any PyInfra configuration runs.

### 3. Configure Domain Nameservers

Point your domain to Hetzner's authoritative nameservers:

1. Log in to your domain registrar
2. Update nameservers to:
   - `hydrogen.ns.hetzner.com`
   - `oxygen.ns.hetzner.com`
   - `helium.ns.hetzner.de`
3. Wait for DNS propagation (typically 1–6 hours, up to 48 hours)

Verify propagation before continuing:

```bash
dig NS proheuvelrug.nl +short
# Should return all three Hetzner nameservers
```

### 4. Create the Terraform State Bucket

The Terraform state backend (S3) must exist before `terraform init` can run — Terraform can't create the bucket that stores its own state. This is a one-time manual step:

1. In Hetzner Cloud Console, go to **Object Storage**
2. Create a bucket named `heuvelrugterraformstate` in `nbg1` (Nuremberg)
3. Create access keys and add them to `.env` (see `.env.example` for variable names)

### 5. Provision Infrastructure

```bash
source .env
cd terraform

terraform init   # Connects to the pre-existing S3 state bucket
terraform plan
terraform apply

# Wait ~1–2 minutes for cloud-init to install Tailscale on the VPS
# Then verify the VPS appeared in your tailnet:
tailscale status | grep nextcloud
```

**Disable Tailscale key expiry for the VPS** — Tailscale device keys expire after 180 days by default. When a device key expires the VPS drops off the tailnet, cutting off all SSH access (since public SSH is blocked). After the VPS appears in your tailnet:

1. Open the [Tailscale admin panel](https://login.tailscale.com/admin/machines)
2. Find the VPS, click **⋯ → Disable key expiry**

This is a one-time step per VPS. The auth key in `.env` is only used when a device initially joins — it can expire without affecting an already-connected VPS.

### 6. Configure Email (Brevo)

Nextcloud uses SMTP to send notifications, password resets, and share emails.

1. Sign up at [https://www.brevo.com](https://www.brevo.com)
2. Go to **SMTP & API → SMTP** and create a new SMTP key
3. Add to `.env`:
   ```bash
   export SMTP_HOST=smtp-relay.brevo.com
   export SMTP_PORT=587
   export SMTP_SECURE=tls
   export SMTP_AUTHTYPE=LOGIN
   export SMTP_NAME=your-brevo-login@example.com   # your Brevo account email (username)
   export SMTP_PASSWORD=your-generated-smtp-key    # the API key, NOT your account password
   export MAIL_FROM_ADDRESS=noreply               # sends as noreply@proheuvelrug.nl
   ```

#### Optional: Verify domain for better deliverability

Verifying your domain with Brevo improves deliverability and removes "sent via brevo.com" footers:

1. In Brevo: **Settings → Senders & IP → Add Domain**, enter `proheuvelrug.nl`
2. Brevo will provide a verification TXT record and two DKIM CNAME records
3. Add them to `.env`:
   ```bash
   export TF_VAR_brevo_verification_code="your-verification-code"
   export TF_VAR_brevo_dkim_key1="b1.your-domain.dkim.brevo.com"
   export TF_VAR_brevo_dkim_key2="b2.your-domain.dkim.brevo.com"
   ```
4. Apply with `cd terraform && terraform apply` — SPF and DMARC records are added automatically

Emails work without domain verification, but deliverability will be lower.

### 7. Deploy VPS

```bash
cd ..  # Return to project root
uv sync

# First-time deployment (creates deploy user, runs all stages)
uv run pyinfra/configure_vps.py --fresh

# Subsequent deployments (skips bootstrap)
uv run pyinfra/configure_vps.py
```

To run a specific stage only:

```bash
uv run pyinfra/configure_vps.py --stage 2-docker
```

### 8. Verify Deployment

```bash
# Get the VPS Tailscale hostname
cd terraform && terraform output tailnet_hostname

# Visit Nextcloud
open https://drive.proheuvelrug.nl

# Check backup service
ssh deploy@<tailscale-hostname> "docker logs nextcloud-backup-1"
```

---

## Updates

Dependency updates (Docker image versions, Terraform providers, Python packages) are handled automatically by [Renovate](https://docs.renovatebot.com/). Renovate opens pull requests when new versions are available.

**Workflow:**

1. Review the Renovate PR (check changelog and release notes)
2. Merge the PR
3. Deploy the update:
   ```bash
   git pull
   source .env
   uv run pyinfra/configure_vps.py
   ```

PyInfra re-renders all templates and restarts affected containers. For major Nextcloud version upgrades, run maintenance commands afterwards:

```bash
ssh deploy@<tailscale-hostname>
docker exec nextcloud-nextcloud-1 su -s /bin/bash www-data -c \
  'php /var/www/html/occ maintenance:repair'
docker exec nextcloud-nextcloud-1 su -s /bin/bash www-data -c \
  'php /var/www/html/occ db:add-missing-indices'
```

---

## Backup Management

### Automated Monitoring

[Healthchecks.io](https://healthchecks.io) (free tier) alerts you if a daily backup doesn't complete:

1. Sign up and create a new check:
   - **Period**: 1 day (backups run daily at 2 AM)
   - **Grace time**: 2 hours (buffer for backup duration)
2. Copy the ping URL and add it to `.env`:
   ```bash
   export HEALTHCHECK_URL=https://hc-ping.com/your-unique-uuid
   ```
3. Redeploy to apply: `uv run pyinfra/configure_vps.py`

After each successful backup, the script pings this URL. If no ping is received within 26 hours, you'll receive an alert via email, Slack, or other configured channels.

### Manual Commands

```bash
ssh deploy@<tailscale-hostname>

# View backup logs
docker logs -f nextcloud-backup-1

# List all snapshots
docker exec nextcloud-backup-1 restic snapshots

# Last snapshot only
docker exec nextcloud-backup-1 restic snapshots --last

# Repository statistics
docker exec nextcloud-backup-1 restic stats --mode restore-size

# Trigger immediate backup
docker exec nextcloud-backup-1 /bin/sh /backup.sh

# Run integrity check
docker exec nextcloud-backup-1 restic check
```

### Retention Policy

Restic prunes old backups automatically after each run:

- **Daily**: last 30 days
- **Weekly**: last 52 weeks (1 year)
- **Monthly**: last 24 months (2 years)

Integrity checks run automatically every Sunday.

---

## Disaster Recovery

### Automated Restore Utility

Run from your local machine — connects to the VPS via SSH and handles all the complexity:

```bash
./restore.sh <tailscale-hostname>
```

Options: full restore, restore to temporary location, restore specific files/directories, database-only restore.

### Manual Restore

#### 1. List snapshots

```bash
docker exec -it nextcloud-backup-1 /bin/sh
restic snapshots
```

#### 2. Restore to temporary location (safe, non-destructive)

```bash
restic restore <snapshot-id> --target /tmp/restore
```

#### 3. Full production restore

> **Warning:** This overwrites production data. Always test with a temporary restore first.
>
> The backup container has read-only access. Run restic directly from the VPS host for production restores.

```bash
# 1. Enable maintenance mode
sudo docker exec nextcloud-nextcloud-1 \
  su -s /bin/bash www-data -c 'php /var/www/html/occ maintenance:mode --on'

# 2. Stop all services
cd /opt/nextcloud && sudo docker compose down

# 3. Load credentials from the root-owned .env
export RESTIC_PASSWORD=$(sudo grep '^RESTIC_PASSWORD=' /opt/nextcloud/.env | cut -d= -f2-)
export AWS_ACCESS_KEY_ID=$(sudo grep '^AWS_ACCESS_KEY_ID=' /opt/nextcloud/.env | cut -d= -f2-)
export AWS_SECRET_ACCESS_KEY=$(sudo grep '^AWS_SECRET_ACCESS_KEY=' /opt/nextcloud/.env | cut -d= -f2-)
export AWS_S3_ENDPOINT=$(sudo grep '^AWS_S3_ENDPOINT=' /opt/nextcloud/.env | cut -d= -f2-)
export AWS_S3_BUCKET=$(sudo grep '^AWS_S3_BUCKET=' /opt/nextcloud/.env | cut -d= -f2-)
export RESTIC_REPOSITORY="s3:${AWS_S3_ENDPOINT}/${AWS_S3_BUCKET}"

# 4. Clear existing data (restic restore is additive, so wipe first for clean state)
MOUNT_POINT=$(sudo findmnt -n -o TARGET /dev/disk/by-id/scsi-0HC_Volume_* | grep -v '/var/lib/docker')
sudo rm -rf ${MOUNT_POINT}/nextcloud_db/*
sudo rm -rf ${MOUNT_POINT}/nextcloud_data/*
sudo rm -rf ${MOUNT_POINT}/ncdata/*

# 5. Restore
sudo -E restic restore <snapshot-id> --target ${MOUNT_POINT}

# 6. Start services and disable maintenance mode
cd /opt/nextcloud && sudo docker compose up -d
sudo docker exec nextcloud-nextcloud-1 \
  su -s /bin/bash www-data -c 'php /var/www/html/occ maintenance:mode --off'
sudo docker exec nextcloud-nextcloud-1 \
  su -s /bin/bash www-data -c 'php /var/www/html/occ maintenance:repair'
```

#### 4. Restore specific files (e.g. accidentally deleted user files)

```bash
# Restore to a temporary location first
docker exec nextcloud-backup-1 restic restore <snapshot-id> \
  --target /tmp/restore \
  --include /mnt/data/ncdata/username/files/important-file.pdf

# Copy to production
cp /tmp/restore/mnt/data/ncdata/username/files/important-file.pdf \
   ${MOUNT_POINT}/ncdata/username/files/

# Fix permissions
chown -R www-data:www-data ${MOUNT_POINT}/ncdata/username/files/

# Trigger Nextcloud file scan to make the file visible
docker exec nextcloud-nextcloud-1 \
  su -s /bin/bash www-data -c 'php /var/www/html/occ files:scan username'
```

#### 5. Complete infrastructure loss

```bash
# 1. Provision fresh infrastructure (~10 min)
source .env && cd terraform && terraform apply
# Wait ~1–2 min for Tailscale, verify: tailscale status | grep nextcloud

# 2. Deploy base configuration (~15 min)
cd .. && uv run pyinfra/configure_vps.py --fresh

# 3. Restore data from backup (follow steps 1–6 above)
```

Estimated total recovery time: 45–90 minutes depending on backup size.

---

## Maintenance

### Checking Service Health

```bash
ssh deploy@<tailscale-hostname>

# All containers and their status
docker ps

# Per-service logs
docker logs nextcloud-nextcloud-1          # Nextcloud app
docker logs nextcloud-nextcloud-db-1       # PostgreSQL
docker logs nextcloud-redis-1              # Redis
docker logs nextcloud-collabora-1          # Collabora Online
docker logs nextcloud-whiteboard-1         # Whiteboard
docker logs nextcloud-signaling-1          # Talk HPB
docker logs nextcloud-coturn-1             # TURN relay
docker logs nextcloud-backup-1             # Backup service
sudo journalctl -u caddy -f               # Caddy (reverse proxy)

# Nextcloud-specific health
docker exec nextcloud-nextcloud-1 \
  su -s /bin/bash www-data -c 'php /var/www/html/occ check'
docker exec nextcloud-nextcloud-1 \
  su -s /bin/bash www-data -c 'php /var/www/html/occ status'

# Verify Collabora is reachable from Nextcloud
docker exec nextcloud-nextcloud-1 curl -sI http://collabora:9980 | head -1

# Check configured Collabora WOPI URL
docker exec nextcloud-nextcloud-1 su -s /bin/bash www-data -c \
  'php /var/www/html/occ config:app:get richdocuments wopi_url'
# Should return: https://office.proheuvelrug.nl
```

### Monitoring Disk Usage

```bash
ssh deploy@<tailscale-hostname> df -h                   # Volume and root disk
ssh deploy@<tailscale-hostname> docker system df        # Docker image/volume usage
ssh deploy@<tailscale-hostname> docker stats --no-stream  # Per-container CPU/RAM
```

### Container Monitoring with Komodo

[Komodo](https://komo.do/) provides a web UI for Docker container monitoring and management, accessible via Tailscale.

**Setup:**

1. Set `PERIPHERY_PASSKEY` in `.env` and redeploy (`--stage 2-docker`)
2. Find the VPS Tailscale address: `ssh deploy@<tailscale-hostname> "tailscale ip"`
3. Register in Komodo Core: add server at `<tailscale-ip>:8120` with the same passkey

Komodo Periphery is bound to the Tailscale IP only and is not reachable from the public internet.

---

## Scaling

### Vertical Scaling

Edit `terraform/hetzner.tf` to change the instance type, then `terraform apply`:

| Type        | vCPU   | RAM        | Users    | Cost                    |
|-------------|--------|------------|----------|-------------------------|
| cpx22       | 4      | 8 GB       | ~20      | ~€15/mo                 |
| **cpx42**   | **8**  | **32 GB**  | **~50**  | **~€25/mo** ← current   |
| cpx52       | 16     | 32 GB      | ~100     | ~€48/mo                 |
| cpx62       | 32     | 64 GB      | 100+     | ~€96/mo                 |

After resizing, update PostgreSQL tuning parameters in `vps/docker/nextcloud.yml.j2` to match the new RAM.

### Storage Expansion

Edit the volume size in `terraform/hetzner.tf` and run `terraform apply`. Hetzner resizes the volume instantly; then expand the filesystem on the VPS:

```bash
ssh deploy@<tailscale-hostname>
DEVICE=$(findmnt -n -o SOURCE /mnt/HC_Volume_* | head -1)
sudo resize2fs $DEVICE
df -h  # Verify
```

Volumes can be expanded but not shrunk.

---

## Cost Estimate

Monthly costs (ex. VAT):

| Resource                                               | Cost        |
|--------------------------------------------------------|-------------|
| VPS (cpx42)                                            | ~€25/mo     |
| Volume (50 GB)                                         | ~€3/mo      |
| Object Storage (base, 1 TB storage + 1 TB egress)      | €4.99/mo    |
| DNS                                                    | Free        |
| **Total**                                              | **~€33/mo** |

---

## Troubleshooting

### Backup Failures

```bash
docker logs nextcloud-backup-1
docker exec nextcloud-backup-1 env | grep AWS
docker exec nextcloud-backup-1 restic snapshots  # Test connection
df -h  # Check disk space
```

### Nextcloud Issues

```bash
docker exec nextcloud-nextcloud-1 \
  su -s /bin/bash www-data -c 'php /var/www/html/occ maintenance:repair'

docker exec nextcloud-nextcloud-1 \
  su -s /bin/bash www-data -c 'php /var/www/html/occ check'

docker logs nextcloud-nextcloud-1 | grep -i error
```

### Email Not Sending

```bash
# Check what Nextcloud has configured for SMTP
docker exec nextcloud-nextcloud-1 \
  su -s /bin/bash www-data -c 'php /var/www/html/occ config:list system' | grep mail

# Test port reachability from the VPS
ssh deploy@<tailscale-hostname> "nc -zv smtp-relay.brevo.com 587"

# View email-related errors
docker exec nextcloud-nextcloud-1 cat /var/www/html/data/nextcloud.log \
  | grep -i "mail\|smtp"
```

**Common causes:**
- **Wrong password** — `SMTP_PASSWORD` must be the Brevo API key, not your Brevo account password
- **Wrong username** — `SMTP_NAME` must be your Brevo account email address (not the API key name)
- **Port blocked** — test with `nc -zv smtp-relay.brevo.com 587`; if it fails, check UFW rules on the VPS
- **Wrong sender domain** — `MAIL_FROM_ADDRESS` is combined with `TF_VAR_domain` to form the sender; verify it matches your Brevo verified domain

### Collabora Not Working

```bash
docker logs nextcloud-collabora-1

# Verify Nextcloud can reach Collabora internally
docker exec nextcloud-nextcloud-1 curl -sI http://collabora:9980 | head -1

# Check configured WOPI URL (must match public Caddy URL)
docker exec nextcloud-nextcloud-1 su -s /bin/bash www-data -c \
  'php /var/www/html/occ config:app:get richdocuments wopi_url'
# Should return: https://office.proheuvelrug.nl
```

### DNS Issues

```bash
dig drive.proheuvelrug.nl
dig NS proheuvelrug.nl +short

# Inspect Terraform DNS state
cd terraform && terraform state show hcloud_zone.domain
```

---

## Security Considerations

**Exposed to internet:**
- Port 80/443 (HTTP/HTTPS) — behind Caddy with automatic HTTPS
- Port 3478/UDP — TURN relay for Nextcloud Talk NAT traversal
- Port 22 (SSH) — **blocked** by Hetzner firewall; only accessible via Tailscale

**Internal only:**
- PostgreSQL (5432), Redis (6379) — Docker network only
- Nextcloud (8080), Collabora (9980), Whiteboard, signaling — localhost, proxied by Caddy
- Komodo Periphery (8120) — Tailscale IP only

**Security features:**
- Automatic HTTPS with HSTS headers
- DNS CAA records restrict certificate issuance to Let's Encrypt
- Encrypted backups (Restic) at rest and in transit
- S3 buckets have `prevent_destroy` lifecycle rule and versioning enabled
- SSH key-based authentication only (password auth disabled)
- Least-privilege deploy user (no direct root access)
- Unattended security upgrades enabled

**Recommended maintenance:**
- Subscribe to [Nextcloud security advisories](https://nextcloud.com/security/advisories/)
- Monitor [Hetzner status](https://status.hetzner.com/)
- Review Nextcloud admin overview periodically for warnings

---

## License

Apache License 2.0 — see [LICENSE](LICENSE) for details.

Third-party components: [Nextcloud (AGPL-3.0)](https://github.com/nextcloud/server/blob/master/COPYING) · [PostgreSQL License](https://www.postgresql.org/about/licence/) · [Redis (BSD-3-Clause)](https://redis.io/docs/about/license/) · [Caddy (Apache-2.0)](https://github.com/caddyserver/caddy/blob/master/LICENSE) · [Collabora Online (MPL-2.0)](https://www.collaboraoffice.com/code/) · [Restic (BSD-2-Clause)](https://github.com/restic/restic/blob/master/LICENSE)
