#!/bin/bash
set -euo pipefail

echo "[$(date)] Starting Nextcloud backup..."

# Backup configuration
BACKUP_DIR="/backup"
DB_BACKUP_FILE="${BACKUP_DIR}/nextcloud_db.sql"
# Use RESTIC_REPOSITORY if set, otherwise construct from endpoint and bucket
RESTIC_REPO="${RESTIC_REPOSITORY:-s3:${AWS_S3_ENDPOINT}/${AWS_S3_BUCKET}}"
# Healthcheck URL (optional)
HEALTHCHECK_URL="${HEALTHCHECK_URL:-}"

# Function to ping healthcheck on failure
ping_failure() {
    if [ -n "$HEALTHCHECK_URL" ]; then
        curl -fsS --retry 3 --max-time 10 "${HEALTHCHECK_URL}/fail" > /dev/null 2>&1 || true
    fi
}

# Trap to ping failure on any exit with non-zero status
trap 'if [ $? -ne 0 ]; then ping_failure; fi' EXIT

# Create backup directory if it doesn't exist
mkdir -p "${BACKUP_DIR}"

# Initialize Restic repository if it doesn't exist
echo "[$(date)] Checking Restic repository..."
if ! restic -r "${RESTIC_REPO}" snapshots &>/dev/null; then
    echo "[$(date)] Initializing Restic repository..."
    restic -r "${RESTIC_REPO}" init
fi

# Container names (from docker-compose project "nextcloud")
NEXTCLOUD_CONTAINER="nextcloud-nextcloud-1"
DB_CONTAINER="nextcloud-nextcloud-db-1"

# Enable Nextcloud maintenance mode
echo "[$(date)] Enabling Nextcloud maintenance mode..."
if ! docker exec -T "$NEXTCLOUD_CONTAINER" su -s /bin/bash www-data -c 'php /var/www/html/occ maintenance:mode --on'; then
    echo "[$(date)] ERROR: Failed to enable maintenance mode. Aborting backup."
    exit 1
fi

# Dump PostgreSQL database
echo "[$(date)] Dumping PostgreSQL database..."
if ! docker exec -T "$DB_CONTAINER" pg_dump -U nextcloud -d nextcloud > "${DB_BACKUP_FILE}"; then
    echo "[$(date)] ERROR: Database dump failed!"
    # Disable maintenance mode before exiting
    docker exec -T "$NEXTCLOUD_CONTAINER" su -s /bin/bash www-data -c 'php /var/www/html/occ maintenance:mode --off' || true
    exit 1
fi

# Backup with Restic
echo "[$(date)] Running Restic backup..."
if ! restic -r "${RESTIC_REPO}" backup \
    --tag nextcloud \
    --tag daily \
    "${BACKUP_DIR}" \
    /mnt/data/nextcloud_db \
    /mnt/data/nextcloud_data \
    /mnt/data/ncdata \
    /mnt/data/redis_data; then
    echo "[$(date)] ERROR: Backup failed!"
    # Disable maintenance mode before exiting
    docker exec -T "$NEXTCLOUD_CONTAINER" su -s /bin/bash www-data -c 'php /var/www/html/occ maintenance:mode --off' || true
    exit 1
fi

# Disable Nextcloud maintenance mode
echo "[$(date)] Disabling Nextcloud maintenance mode..."
docker exec -T "$NEXTCLOUD_CONTAINER" su -s /bin/bash www-data -c 'php /var/www/html/occ maintenance:mode --off' || true

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

# Ping healthcheck service if URL is configured
if [ -n "$HEALTHCHECK_URL" ]; then
    echo "[$(date)] Pinging healthcheck service..."
    if curl -fsS --retry 3 --max-time 10 "$HEALTHCHECK_URL" > /dev/null 2>&1; then
        echo "[$(date)] Healthcheck ping successful"
    else
        echo "[$(date)] WARNING: Healthcheck ping failed (non-fatal)"
    fi
fi
