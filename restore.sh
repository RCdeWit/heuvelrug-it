#!/bin/bash
set -euo pipefail

# Colors for better UX
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
NEXTCLOUD_DIR="${NEXTCLOUD_DIR:-/opt/nextcloud}"
# Container names derived from Docker Compose project name (defaults to directory basename).
# Override by setting COMPOSE_PROJECT_NAME to match what was set during deployment.
_PROJECT="${COMPOSE_PROJECT_NAME:-nextcloud}"
NEXTCLOUD_CONTAINER="${_PROJECT}-nextcloud-1"
DB_CONTAINER="${_PROJECT}-nextcloud-db-1"
RESTORE_TEMP="/tmp/restore_$(date +%s)"

# VPS connection (set via command line)
VPS_HOST=""
VPS_USER="deploy"

# Helper functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

confirm() {
    local prompt="$1"
    local default="${2:-n}"
    local response

    if [[ "$default" == "y" ]]; then
        read -p "$prompt [Y/n] " response
        response=${response:-y}
    else
        read -p "$prompt [y/N] " response
        response=${response:-n}
    fi

    [[ "$response" =~ ^[Yy] ]]
}

# Execute command on VPS
ssh_exec() {
    ssh "${VPS_USER}@${VPS_HOST}" "$@"
}

# Execute command on VPS with sudo
ssh_exec_sudo() {
    ssh "${VPS_USER}@${VPS_HOST}" "sudo bash -c '$1'"
}

check_requirements() {
    log_info "Checking local requirements..."

    # Check if ssh is available
    if ! command -v ssh &> /dev/null; then
        log_error "ssh is not installed."
        exit 1
    fi

    # Check if we can connect to VPS
    if ! ssh -o ConnectTimeout=5 -o BatchMode=yes "${VPS_USER}@${VPS_HOST}" echo "OK" &> /dev/null; then
        log_error "Cannot connect to VPS at ${VPS_USER}@${VPS_HOST}"
        log_error "Make sure SSH key authentication is set up."
        exit 1
    fi

    log_success "Local requirements met"
}

check_vps_requirements() {
    log_info "Checking VPS requirements..."

    # Check if Nextcloud directory exists
    if ! ssh_exec "test -d $NEXTCLOUD_DIR"; then
        log_error "Nextcloud directory not found on VPS: $NEXTCLOUD_DIR"
        exit 1
    fi

    # Check if restic is installed
    if ! ssh_exec "command -v restic &> /dev/null"; then
        log_error "restic is not installed on VPS."
        exit 1
    fi

    # Check if docker is installed
    if ! ssh_exec "command -v docker &> /dev/null"; then
        log_error "docker is not installed on VPS."
        exit 1
    fi

    log_success "VPS requirements met"
}

load_env_vars() {
    log_info "Loading environment variables from VPS..."

    # Extract environment variables from VPS
    RESTIC_PASSWORD=$(ssh_exec_sudo "grep '^RESTIC_PASSWORD=' ${NEXTCLOUD_DIR}/.env | cut -d= -f2-")
    AWS_ACCESS_KEY_ID=$(ssh_exec_sudo "grep '^AWS_ACCESS_KEY_ID=' ${NEXTCLOUD_DIR}/.env | cut -d= -f2-")
    AWS_SECRET_ACCESS_KEY=$(ssh_exec_sudo "grep '^AWS_SECRET_ACCESS_KEY=' ${NEXTCLOUD_DIR}/.env | cut -d= -f2-")
    AWS_S3_ENDPOINT=$(ssh_exec_sudo "grep '^AWS_S3_ENDPOINT=' ${NEXTCLOUD_DIR}/.env | cut -d= -f2-")
    AWS_S3_BUCKET=$(ssh_exec_sudo "grep '^AWS_S3_BUCKET=' ${NEXTCLOUD_DIR}/.env | cut -d= -f2-")
    RESTIC_REPOSITORY="s3:${AWS_S3_ENDPOINT}/${AWS_S3_BUCKET}"

    # Verify we got all the variables
    if [[ -z "$RESTIC_PASSWORD" ]] || [[ -z "$AWS_ACCESS_KEY_ID" ]] || [[ -z "$AWS_SECRET_ACCESS_KEY" ]]; then
        log_error "Failed to load required environment variables from .env file"
        exit 1
    fi

    # Export for restic commands
    export RESTIC_PASSWORD
    export AWS_ACCESS_KEY_ID
    export AWS_SECRET_ACCESS_KEY
    export RESTIC_REPOSITORY

    log_success "Environment variables loaded"
}

list_snapshots() {
    log_info "Fetching available snapshots..."
    echo ""

    # Run restic locally to list snapshots
    ssh_exec "export RESTIC_PASSWORD='$RESTIC_PASSWORD' AWS_ACCESS_KEY_ID='$AWS_ACCESS_KEY_ID' AWS_SECRET_ACCESS_KEY='$AWS_SECRET_ACCESS_KEY' RESTIC_REPOSITORY='$RESTIC_REPOSITORY' && restic snapshots --tag nextcloud"
}

select_snapshot() {
    local snapshot_id
    echo "" >&2
    echo "==========================================" >&2
    log_info "Enter the snapshot ID from the list above" >&2
    log_info "You can use the full ID or just the first 8 characters" >&2
    echo "==========================================" >&2
    echo "" >&2
    read -p "Snapshot ID: " snapshot_id

    if [[ -z "$snapshot_id" ]]; then
        log_error "No snapshot ID provided" >&2
        exit 1
    fi

    # Verify snapshot exists
    log_info "Verifying snapshot ID..." >&2
    if ! ssh_exec "export RESTIC_PASSWORD='$RESTIC_PASSWORD' AWS_ACCESS_KEY_ID='$AWS_ACCESS_KEY_ID' AWS_SECRET_ACCESS_KEY='$AWS_SECRET_ACCESS_KEY' RESTIC_REPOSITORY='$RESTIC_REPOSITORY' && restic snapshots $snapshot_id" &> /dev/null; then
        log_error "Invalid snapshot ID: $snapshot_id" >&2
        log_error "Please check the ID from the list above and try again" >&2
        exit 1
    fi

    log_success "Snapshot ID verified: $snapshot_id" >&2
    echo "$snapshot_id"
}

show_restore_menu() {
    echo "" >&2
    echo "==========================================" >&2
    echo "  Nextcloud Backup Restoration Utility" >&2
    echo "==========================================" >&2
    echo "" >&2
    echo "VPS: ${VPS_USER}@${VPS_HOST}" >&2
    echo "" >&2
    echo "What type of restore would you like to perform?" >&2
    echo "" >&2
    echo "  1) Full restore (complete disaster recovery)" >&2
    echo "  2) Restore to temporary location on VPS (inspect only)" >&2
    echo "  3) Restore specific files/directories" >&2
    echo "  4) Database only" >&2
    echo "  5) Exit" >&2
    echo "" >&2
    read -p "Enter your choice [1-5]: " choice
    echo "$choice"
}

get_mount_point() {
    local mount_point
    mount_point=$(ssh_exec_sudo "findmnt -n -o TARGET /dev/disk/by-id/scsi-0HC_Volume_* 2>/dev/null | grep -v '/var/lib/docker' | head -n 1")

    if [[ -z "$mount_point" ]]; then
        log_error "Could not find Hetzner volume mount point"
        exit 1
    fi

    echo "$mount_point"
}

enable_maintenance_mode() {
    log_info "Enabling Nextcloud maintenance mode..."
    ssh_exec_sudo "docker exec ${NEXTCLOUD_CONTAINER} su -s /bin/bash www-data -c 'php /var/www/html/occ maintenance:mode --on'" || true
    log_success "Maintenance mode enabled"
}

disable_maintenance_mode() {
    log_info "Disabling Nextcloud maintenance mode..."
    ssh_exec_sudo "docker exec ${NEXTCLOUD_CONTAINER} su -s /bin/bash www-data -c 'php /var/www/html/occ maintenance:mode --off'" || true
    log_success "Maintenance mode disabled"
}

stop_services() {
    log_info "Stopping Docker services..."
    ssh_exec_sudo "cd $NEXTCLOUD_DIR && docker compose down"
    log_success "Services stopped"
}

start_services() {
    log_info "Starting Docker services..."
    ssh_exec_sudo "cd $NEXTCLOUD_DIR && docker compose up -d"
    log_success "Services started"
}

run_maintenance() {
    log_info "Running Nextcloud maintenance and repair..."
    ssh_exec_sudo "docker exec ${NEXTCLOUD_CONTAINER} su -s /bin/bash www-data -c 'php /var/www/html/occ maintenance:repair'"
    log_success "Maintenance completed"
}

restore_full() {
    local snapshot_id=$1
    local mount_point

    log_warning "=========================================="
    log_warning "  FULL RESTORE - DESTRUCTIVE OPERATION"
    log_warning "=========================================="
    log_warning "This will:"
    log_warning "  1. Stop all Nextcloud services on ${VPS_HOST}"
    log_warning "  2. Delete all current data"
    log_warning "  3. Restore from snapshot: $snapshot_id"
    log_warning "  4. Restart services"
    echo ""

    if ! confirm "Are you absolutely sure you want to proceed?" "n"; then
        log_info "Restore cancelled"
        exit 0
    fi

    # Double confirmation
    log_warning "This action cannot be undone!"
    read -p "Type 'YES' to confirm: " confirmation
    if [[ "$confirmation" != "YES" ]]; then
        log_info "Restore cancelled"
        exit 0
    fi

    # Get mount point
    mount_point=$(get_mount_point)
    log_info "Using mount point: $mount_point"

    # Enable maintenance mode first
    enable_maintenance_mode

    # Stop all services
    stop_services

    # Clear existing data (user files and Nextcloud app data only, NOT database)
    log_info "Clearing user data directories..."
    ssh_exec_sudo "rm -rf ${mount_point}/nextcloud_data/*"
    ssh_exec_sudo "rm -rf ${mount_point}/ncdata/*"
    log_success "User data directories cleared"

    # Restore user files and Nextcloud data from snapshot
    log_info "Restoring user files and Nextcloud data from snapshot $snapshot_id..."
    log_info "This may take several minutes depending on backup size..."
    ssh_exec "export RESTIC_PASSWORD='$RESTIC_PASSWORD' AWS_ACCESS_KEY_ID='$AWS_ACCESS_KEY_ID' AWS_SECRET_ACCESS_KEY='$AWS_SECRET_ACCESS_KEY' RESTIC_REPOSITORY='$RESTIC_REPOSITORY' && sudo -E restic restore $snapshot_id --target $mount_point --include /mnt/data/nextcloud_data --include /mnt/data/ncdata --include /backup"
    log_success "Files restored"

    # Start services (needed for database container)
    start_services

    # Wait for database to be ready
    log_info "Waiting for database to be ready..."
    sleep 15

    # Restore database from SQL dump
    log_info "Restoring database from SQL dump..."
    # Drop and recreate database using echo to pipe SQL commands
    ssh_exec_sudo "echo 'DROP DATABASE IF EXISTS nextcloud; CREATE DATABASE nextcloud;' | docker exec -i ${DB_CONTAINER} psql -U nextcloud -d postgres"
    # Import SQL dump
    ssh_exec_sudo "docker exec -i ${DB_CONTAINER} psql -U nextcloud -d nextcloud < ${mount_point}/backup/nextcloud_db.sql"

    # Get database user from config and grant permissions
    log_info "Fixing database permissions..."
    local db_user
    db_user=$(ssh_exec_sudo "docker exec ${NEXTCLOUD_CONTAINER} grep \"'dbuser'\" /var/www/html/config/config.php | cut -d\\\" -f2")
    if [[ -n "$db_user" ]]; then
        ssh_exec_sudo "docker exec ${DB_CONTAINER} psql -U nextcloud -d nextcloud -c 'GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO $db_user; GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO $db_user;'"
    fi

    # Ensure installed flag is set in config.php
    log_info "Setting installed flag in config.php..."
    ssh_exec_sudo "docker exec ${NEXTCLOUD_CONTAINER} bash -c 'cd /var/www/html/config && if ! grep -q \"installed\" config.php; then cp config.php config.php.bak && awk \"/);/{print \\\"  \\047installed\\047 => true,\\\"; print; next} 1\" config.php.bak > config.php && chown www-data:www-data config.php; fi'"

    log_success "Database restored"

    # Clean up SQL dump
    ssh_exec_sudo "rm -rf ${mount_point}/backup"

    # Restart Nextcloud container to apply all IaC configurations from entrypoint
    log_info "Restarting Nextcloud container to apply IaC configurations..."
    ssh_exec_sudo "docker restart ${NEXTCLOUD_CONTAINER}"
    sleep 20  # Wait for container to fully restart and entrypoint to run

    # Run maintenance
    run_maintenance

    # Disable maintenance mode
    disable_maintenance_mode

    log_success "=========================================="
    log_success "  Full restore completed successfully!"
    log_success "=========================================="
    log_success "Your Nextcloud instance should now be accessible"
}

restore_to_temp() {
    local snapshot_id=$1

    log_info "Restoring snapshot $snapshot_id to temporary location on VPS..."
    log_info "Restore location: $RESTORE_TEMP"

    ssh_exec "export RESTIC_PASSWORD='$RESTIC_PASSWORD' AWS_ACCESS_KEY_ID='$AWS_ACCESS_KEY_ID' AWS_SECRET_ACCESS_KEY='$AWS_SECRET_ACCESS_KEY' RESTIC_REPOSITORY='$RESTIC_REPOSITORY' && mkdir -p $RESTORE_TEMP && restic restore $snapshot_id --target $RESTORE_TEMP"

    log_success "Restore completed!"
    log_info "Files restored to: ${VPS_HOST}:${RESTORE_TEMP}"
    log_info "To browse: ssh ${VPS_USER}@${VPS_HOST} 'cd $RESTORE_TEMP && ls -la'"
    log_warning "Remember to delete when done: ssh ${VPS_USER}@${VPS_HOST} 'sudo rm -rf $RESTORE_TEMP'"
}

restore_specific() {
    local snapshot_id=$1
    local path_to_restore

    echo ""
    log_info "What would you like to restore?"
    log_info "Examples:"
    log_info "  - User files: /mnt/data/ncdata/username/files/"
    log_info "  - Database: /backup/nextcloud_db.sql"
    log_info "  - Config: /mnt/data/nextcloud_data/config/"
    echo ""
    read -p "Enter path to restore: " path_to_restore

    if [[ -z "$path_to_restore" ]]; then
        log_error "No path provided"
        exit 1
    fi

    log_info "Restoring $path_to_restore to $RESTORE_TEMP on VPS..."

    ssh_exec "export RESTIC_PASSWORD='$RESTIC_PASSWORD' AWS_ACCESS_KEY_ID='$AWS_ACCESS_KEY_ID' AWS_SECRET_ACCESS_KEY='$AWS_SECRET_ACCESS_KEY' RESTIC_REPOSITORY='$RESTIC_REPOSITORY' && mkdir -p $RESTORE_TEMP && restic restore $snapshot_id --target $RESTORE_TEMP --include '$path_to_restore'"

    log_success "Restore completed!"
    log_info "Files restored to: ${VPS_HOST}:${RESTORE_TEMP}"
    echo ""
    log_info "To copy to production on VPS:"

    if [[ "$path_to_restore" == *"/ncdata/"* ]]; then
        local mount_point
        mount_point=$(get_mount_point)
        log_info "  1. SSH into VPS: ssh ${VPS_USER}@${VPS_HOST}"
        log_info "  2. Copy files: sudo cp -r $RESTORE_TEMP/* $mount_point/"
        log_info "  3. Fix permissions: sudo chown -R www-data:www-data $mount_point/ncdata/"
        log_info "  4. Scan files: sudo docker exec ${NEXTCLOUD_CONTAINER} su -s /bin/bash www-data -c 'php /var/www/html/occ files:scan --all'"
    else
        log_info "  1. SSH into VPS: ssh ${VPS_USER}@${VPS_HOST}"
        log_info "  2. Review files in $RESTORE_TEMP and copy manually as needed"
    fi

    log_warning "Remember to delete temp files when done: ssh ${VPS_USER}@${VPS_HOST} 'sudo rm -rf $RESTORE_TEMP'"
}

restore_database() {
    local snapshot_id=$1

    log_warning "=========================================="
    log_warning "  DATABASE RESTORE - DESTRUCTIVE OPERATION"
    log_warning "=========================================="
    log_warning "This will restore only the PostgreSQL database."
    log_warning "User files will NOT be affected."
    echo ""

    if ! confirm "Proceed with database restore?" "n"; then
        log_info "Restore cancelled"
        exit 0
    fi

    # Enable maintenance mode
    enable_maintenance_mode

    # Restore database dump to temp location
    log_info "Extracting database dump from snapshot..."
    ssh_exec "export RESTIC_PASSWORD='$RESTIC_PASSWORD' AWS_ACCESS_KEY_ID='$AWS_ACCESS_KEY_ID' AWS_SECRET_ACCESS_KEY='$AWS_SECRET_ACCESS_KEY' RESTIC_REPOSITORY='$RESTIC_REPOSITORY' && mkdir -p $RESTORE_TEMP && restic restore $snapshot_id --target $RESTORE_TEMP --include /backup/nextcloud_db.sql"

    # Check if database dump exists
    if ! ssh_exec "test -f ${RESTORE_TEMP}/backup/nextcloud_db.sql"; then
        log_error "Database dump not found in snapshot"
        disable_maintenance_mode
        exit 1
    fi

    # Restore database from SQL dump
    log_info "Restoring database from SQL dump..."
    # Drop and recreate database using echo to pipe SQL commands
    ssh_exec_sudo "echo 'DROP DATABASE IF EXISTS nextcloud; CREATE DATABASE nextcloud;' | docker exec -i ${DB_CONTAINER} psql -U nextcloud -d postgres"
    # Import SQL dump
    ssh_exec_sudo "docker exec -i ${DB_CONTAINER} psql -U nextcloud -d nextcloud < ${RESTORE_TEMP}/backup/nextcloud_db.sql"

    # Get database user from config and grant permissions
    log_info "Fixing database permissions..."
    local db_user
    db_user=$(ssh_exec_sudo "docker exec ${NEXTCLOUD_CONTAINER} grep \"'dbuser'\" /var/www/html/config/config.php | cut -d\\\" -f2")
    if [[ -n "$db_user" ]]; then
        ssh_exec_sudo "docker exec ${DB_CONTAINER} psql -U nextcloud -d nextcloud -c 'GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO $db_user; GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO $db_user;'"
    fi

    # Ensure installed flag is set in config.php
    log_info "Setting installed flag in config.php..."
    ssh_exec_sudo "docker exec ${NEXTCLOUD_CONTAINER} bash -c 'cd /var/www/html/config && if ! grep -q \"installed\" config.php; then cp config.php config.php.bak && awk \"/);/{print \\\"  \\047installed\\047 => true,\\\"; print; next} 1\" config.php.bak > config.php && chown www-data:www-data config.php; fi'"

    log_success "Database restored"

    # Cleanup
    ssh_exec "rm -rf $RESTORE_TEMP"

    # Run maintenance
    run_maintenance

    # Disable maintenance mode
    disable_maintenance_mode

    log_success "Database restore completed successfully!"
}

show_usage() {
    echo "Usage: $0 <vps-ip-address>"
    echo ""
    echo "Example:"
    echo "  $0 123.45.67.89"
    echo ""
    echo "Note: Use the IP address of your VPS, not the hostname."
    echo "The script will connect as user 'deploy' by default."
    echo "Make sure SSH key authentication is configured."
    exit 1
}

main() {
    # Check command line arguments
    if [[ $# -ne 1 ]]; then
        show_usage
    fi

    VPS_HOST="$1"

    echo ""
    log_info "Nextcloud Backup Restoration Utility"
    echo ""

    # Check local requirements
    check_requirements

    # Check VPS requirements
    check_vps_requirements

    # Load environment variables from VPS
    load_env_vars

    # List available snapshots
    list_snapshots

    # Show menu
    choice=$(show_restore_menu)

    case $choice in
        1)
            snapshot_id=$(select_snapshot)
            restore_full "$snapshot_id"
            ;;
        2)
            snapshot_id=$(select_snapshot)
            restore_to_temp "$snapshot_id"
            ;;
        3)
            snapshot_id=$(select_snapshot)
            restore_specific "$snapshot_id"
            ;;
        4)
            snapshot_id=$(select_snapshot)
            restore_database "$snapshot_id"
            ;;
        5)
            log_info "Exiting..."
            exit 0
            ;;
        *)
            log_error "Invalid choice"
            exit 1
            ;;
    esac
}

# Run main function
main "$@"
