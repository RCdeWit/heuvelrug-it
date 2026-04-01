#!/bin/bash
set -euo pipefail

# ── Colors (auto-disabled when stdout is not a terminal, e.g. cron log) ───────
if [ -t 1 ]; then
    RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
    CYAN='\033[0;36m'; BOLD='\033[1m'; DIM='\033[2m'; RESET='\033[0m'
else
    RED=''; GREEN=''; YELLOW=''; CYAN=''; BOLD=''; DIM=''; RESET=''
fi

ts()        { date '+%H:%M:%S'; }
log_step()  { printf "${CYAN}[%s]${RESET} %s\n" "$(ts)" "$1"; }
log_ok()    { printf "${GREEN}[%s] ✓ %s${RESET}\n" "$(ts)" "$1"; }
log_warn()  { printf "${YELLOW}[%s] ⚠ %s${RESET}\n" "$(ts)" "$1"; }
log_error() { printf "${RED}[%s] ✗ %s${RESET}\n" "$(ts)" "$1" >&2; }

# ── Configuration ─────────────────────────────────────────────────────────────
BACKUP_DIR="/backup"
DB_BACKUP_FILE="${BACKUP_DIR}/nextcloud_db.sql"
RESTIC_REPO="${RESTIC_REPOSITORY:-s3:${AWS_S3_ENDPOINT}/${AWS_S3_BUCKET}}"
HEALTHCHECK_URL="${HEALTHCHECK_URL:-}"
NEXTCLOUD_CONTAINER="nextcloud-nextcloud-1"
DB_CONTAINER="nextcloud-nextcloud-db-1"

START_TIME=$(date +%s)

# ── Header ────────────────────────────────────────────────────────────────────
printf "\n${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}\n"
printf "${BOLD}  🗄️  Nextcloud Backup${RESET}  ${DIM}$(date '+%Y-%m-%d')${RESET}\n"
printf "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}\n\n"

# ── Healthcheck failure ping ──────────────────────────────────────────────────
ping_failure() {
    if [ -n "$HEALTHCHECK_URL" ]; then
        curl -fsS --retry 3 --max-time 10 "${HEALTHCHECK_URL}/fail" > /dev/null 2>&1 || true
    fi
}

trap 'if [ $? -ne 0 ]; then ping_failure; fi' EXIT

mkdir -p "${BACKUP_DIR}"

# ── Restic repository ─────────────────────────────────────────────────────────
log_step "Checking restic repository..."
if ! restic -r "${RESTIC_REPO}" cat config &>/dev/null; then
    log_step "Initializing restic repository..."
    restic -r "${RESTIC_REPO}" init
    log_ok "Repository initialized"
else
    log_ok "Repository ready"
fi

# ── Maintenance mode ──────────────────────────────────────────────────────────
log_step "Enabling maintenance mode..."
if ! docker exec "$NEXTCLOUD_CONTAINER" su -s /bin/bash www-data -c 'php /var/www/html/occ maintenance:mode --on'; then
    log_error "Failed to enable maintenance mode — aborting"
    exit 1
fi
log_ok "Maintenance mode enabled"

# ── Database dump ─────────────────────────────────────────────────────────────
log_step "Dumping PostgreSQL database..."
if ! docker exec "$DB_CONTAINER" pg_dump -U nextcloud -d nextcloud > "${DB_BACKUP_FILE}"; then
    log_error "Database dump failed"
    docker exec "$NEXTCLOUD_CONTAINER" su -s /bin/bash www-data -c 'php /var/www/html/occ maintenance:mode --off' || true
    exit 1
fi
log_ok "Database dumped"

# ── Restic backup ─────────────────────────────────────────────────────────────
log_step "Running restic backup..."
if ! restic -r "${RESTIC_REPO}" backup \
    --tag nextcloud \
    --tag daily \
    "${BACKUP_DIR}" \
    /mnt/data/nextcloud_db \
    /mnt/data/nextcloud_data \
    /mnt/data/ncdata \
    /mnt/data/redis_data; then
    log_error "Restic backup failed"
    docker exec "$NEXTCLOUD_CONTAINER" su -s /bin/bash www-data -c 'php /var/www/html/occ maintenance:mode --off' || true
    exit 1
fi
log_ok "Backup complete"

# ── Maintenance mode off ──────────────────────────────────────────────────────
log_step "Disabling maintenance mode..."
docker exec "$NEXTCLOUD_CONTAINER" su -s /bin/bash www-data -c 'php /var/www/html/occ maintenance:mode --off' || true
log_ok "Maintenance mode disabled"

# ── Prune ─────────────────────────────────────────────────────────────────────
log_step "Pruning old snapshots..."
restic -r "${RESTIC_REPO}" forget \
    --keep-daily ${BACKUP_RETENTION_DAYS} \
    --keep-weekly 52 \
    --keep-monthly 24 \
    --prune
log_ok "Pruning complete"

# ── Integrity check (Sundays only) ───────────────────────────────────────────
if [ "$(date +%u)" -eq 7 ]; then
    log_step "Running integrity check..."
    restic -r "${RESTIC_REPO}" check
    log_ok "Integrity check passed"
fi

rm -f "${DB_BACKUP_FILE}"

# ── Repository stats ──────────────────────────────────────────────────────────
log_step "Repository stats:"
restic -r "${RESTIC_REPO}" stats --mode restore-size

# ── Footer ────────────────────────────────────────────────────────────────────
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))
MINUTES=$((DURATION / 60))
SECONDS=$((DURATION % 60))

printf "\n${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}\n"
printf "${GREEN}${BOLD}  ✅ Backup completed successfully${RESET}  ${DIM}${MINUTES}m ${SECONDS}s${RESET}\n"
printf "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}\n\n"

# ── Healthcheck success ping ──────────────────────────────────────────────────
if [ -n "$HEALTHCHECK_URL" ]; then
    if curl -fsS --retry 3 --max-time 10 "$HEALTHCHECK_URL" > /dev/null 2>&1; then
        log_ok "Healthcheck pinged"
    else
        log_warn "Healthcheck ping failed (non-fatal)"
    fi
fi
