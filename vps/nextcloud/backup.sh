#!/bin/bash
set -euo pipefail

echo "[$(date)] Starting Nextcloud backup..."

# Backup configuration
BACKUP_DIR="/backup"
DB_BACKUP_FILE="${BACKUP_DIR}/nextcloud_db.sql"
# Use RESTIC_REPOSITORY if set, otherwise construct from endpoint and bucket
RESTIC_REPO="${RESTIC_REPOSITORY:-s3:${AWS_S3_ENDPOINT}/${AWS_S3_BUCKET}}"

# Create backup directory if it doesn't exist
mkdir -p "${BACKUP_DIR}"

# Initialize Restic repository if it doesn't exist
echo "[$(date)] Checking Restic repository..."
if ! restic -r "${RESTIC_REPO}" snapshots &>/dev/null; then
    echo "[$(date)] Initializing Restic repository..."
    restic -r "${RESTIC_REPO}" init
fi

# Enable Nextcloud maintenance mode
echo "[$(date)] Enabling Nextcloud maintenance mode..."
docker exec nextcloud-nextcloud-1 su -s /bin/bash www-data -c 'php /var/www/html/occ maintenance:mode --on' || true

# Dump PostgreSQL database
echo "[$(date)] Dumping PostgreSQL database..."
docker exec nextcloud-nextcloud-db-1 pg_dump -U nextcloud -d nextcloud > "${DB_BACKUP_FILE}"

# Backup with Restic
echo "[$(date)] Running Restic backup..."
restic -r "${RESTIC_REPO}" backup \
    --tag nextcloud \
    --tag daily \
    "${BACKUP_DIR}" \
    /mnt/data/nextcloud_db \
    /mnt/data/nextcloud_data \
    /mnt/data/ncdata

# Disable Nextcloud maintenance mode
echo "[$(date)] Disabling Nextcloud maintenance mode..."
docker exec nextcloud-nextcloud-1 su -s /bin/bash www-data -c 'php /var/www/html/occ maintenance:mode --off' || true

# Prune old backups
echo "[$(date)] Pruning old backups..."
restic -r "${RESTIC_REPO}" forget \
    --keep-daily ${BACKUP_RETENTION_DAYS} \
    --keep-weekly 52 \
    --keep-monthly 24 \
    --prune

# Check repository integrity (weekly on Sundays)
if [ "$(date +%u)" -eq 7 ]; then
    echo "[$(date)] Running repository integrity check..."
    restic -r "${RESTIC_REPO}" check
fi

# Clean up database dump
rm -f "${DB_BACKUP_FILE}"

echo "[$(date)] Backup completed successfully!"

# Show repository stats
restic -r "${RESTIC_REPO}" stats --mode restore-size
