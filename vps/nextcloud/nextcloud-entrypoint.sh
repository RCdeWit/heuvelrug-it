#!/bin/bash
set -e

# Run original entrypoint in background to let Nextcloud initialize
/entrypoint.sh apache2-foreground &
NEXTCLOUD_PID=$!

# Wait for Nextcloud config to be created
echo "Waiting for Nextcloud to initialize..."
while [ ! -f /var/www/html/config/config.php ]; do
    sleep 5
done
sleep 15

# Apply configuration settings not available via environment variables
echo "Applying custom configuration..."
# Background jobs mode (for dedicated cron container)
su -s /bin/bash www-data -c 'php /var/www/html/occ config:system:set backgroundjobs_mode --value="cron"' || true
# Disable skeleton directory (empty user folders on creation)
su -s /bin/bash www-data -c 'php /var/www/html/occ config:system:set skeletondirectory --value=""' || true

# Note: The following settings are now configured via nextcloud.config.php:
# - trusted_proxies, forwarded_for_headers
# - maintenance_window_start, default_phone_region
# - memcache.local (APCu), memcache.distributed/locking (Redis)
# - filelocking.enabled, log_query, loglevel
#
# SMTP settings are configured automatically by the Nextcloud Docker image
# via SMTP_HOST, SMTP_PORT, SMTP_SECURE, SMTP_NAME, SMTP_PASSWORD,
# MAIL_FROM_ADDRESS, and MAIL_DOMAIN environment variables

# Disable unwanted default apps (see README.md for full app documentation)
echo "Disabling unwanted apps..."
su -s /bin/bash www-data -c 'php /var/www/html/occ app:disable app_api' 2>/dev/null || true
su -s /bin/bash www-data -c 'php /var/www/html/occ app:disable photos' 2>/dev/null || true

# Install Nextcloud Office (uses external Collabora container)
echo "Installing Nextcloud Office..."
# Ensure built-in CODE server is NOT installed
su -s /bin/bash www-data -c 'php /var/www/html/occ app:disable richdocumentscode' 2>/dev/null || true
su -s /bin/bash www-data -c 'php /var/www/html/occ app:remove richdocumentscode' 2>/dev/null || true
# Install and enable Nextcloud Office
su -s /bin/bash www-data -c 'php /var/www/html/occ app:install richdocuments' 2>/dev/null || true
su -s /bin/bash www-data -c 'php /var/www/html/occ app:enable richdocuments' || true
# Configure to use external Collabora server
echo "Configuring external Collabora server..."
su -s /bin/bash www-data -c 'php /var/www/html/occ config:app:set richdocuments wopi_url --value=https://office.{{ domain }}' || true
su -s /bin/bash www-data -c 'php /var/www/html/occ config:app:set richdocuments public_wopi_url --value=https://office.{{ domain }}' || true
su -s /bin/bash www-data -c 'php /var/www/html/occ config:app:set richdocuments disable_certificate_verification --value=""' || true

# Security: Restrict WOPI requests to only accept from Collabora container
# This prevents unauthorized servers from fetching document content via WOPI
# Docker Compose networks typically use 172.16.0.0/12 range
echo "Configuring WOPI allowlist for Collabora..."
su -s /bin/bash www-data -c 'php /var/www/html/occ config:app:set richdocuments wopi_allowlist --value="172.16.0.0/12"' || true

# Install and configure Nextcloud Talk for video conferencing
echo "Installing Nextcloud Talk..."
su -s /bin/bash www-data -c 'php /var/www/html/occ app:install spreed' 2>/dev/null || true
su -s /bin/bash www-data -c 'php /var/www/html/occ app:enable spreed' || true

# Wait for Talk app to be fully available
echo "Waiting for Talk app to be ready..."
sleep 5

# Validate Talk secrets are set
if [ -z "${TURN_SECRET}" ]; then
    echo "ERROR: TURN_SECRET is not set!"
fi
if [ -z "${SIGNALING_SECRET}" ]; then
    echo "ERROR: SIGNALING_SECRET is not set!"
fi

# Configure STUN server (use our own coturn)
# Format: hostname:port (UI adds the stun: prefix)
echo "Configuring Talk STUN server..."
su -s /bin/bash www-data -c 'php /var/www/html/occ config:app:set spreed stun_servers --value="[\"turn.{{ domain }}:3478\"]"'

# Configure TURN server with shared secret
# Format: hostname:port (UI adds the turn: prefix)
echo "Configuring Talk TURN server..."
if [ -n "${TURN_SECRET}" ]; then
    su -s /bin/bash www-data -c "php /var/www/html/occ config:app:set spreed turn_servers --value='[{\"server\":\"turn.{{ domain }}:3478\",\"secret\":\"${TURN_SECRET}\",\"protocols\":\"udp,tcp\"}]'"
fi

# Configure High Performance Backend (signaling server)
# Format: {"servers":[{"server":"url","verify":bool}],"secret":"shared-secret"}
echo "Configuring Talk High Performance Backend..."
if [ -n "${SIGNALING_SECRET}" ]; then
    su -s /bin/bash www-data -c "php /var/www/html/occ config:app:set spreed signaling_servers --value='{\"servers\":[{\"server\":\"https://signaling.{{ domain }}/\",\"verify\":true}],\"secret\":\"${SIGNALING_SECRET}\"}'"
else
    echo "ERROR: Cannot configure HPB - SIGNALING_SECRET env var is empty!"
fi

# Install and configure Client Push (notify_push) for real-time sync
echo "Installing Client Push (notify_push)..."
su -s /bin/bash www-data -c 'php /var/www/html/occ app:install notify_push' 2>/dev/null || true
su -s /bin/bash www-data -c 'php /var/www/html/occ app:enable notify_push' || true

# Run notify_push setup in background with retries
# The push daemon runs in a separate container and needs time to start
# This runs in the background so it doesn't block container startup
(
    echo "Waiting for notify_push daemon to be ready..."
    sleep 30  # Give the daemon container time to start

    for i in $(seq 1 12); do
        echo "Attempting notify_push setup (attempt $i/12)..."
        if su -s /bin/bash www-data -c 'php /var/www/html/occ notify_push:setup https://drive.{{ domain }}/push' 2>&1; then
            echo "Client Push configured successfully!"
            break
        fi
        echo "notify_push daemon not ready yet, waiting 30 seconds..."
        sleep 30
    done
) &

# Install two-factor authentication providers
echo "Installing TOTP two-factor authentication..."
su -s /bin/bash www-data -c 'php /var/www/html/occ app:install twofactor_totp' 2>/dev/null || true
su -s /bin/bash www-data -c 'php /var/www/html/occ app:enable twofactor_totp' || true
# Enable bundled backup codes app
su -s /bin/bash www-data -c 'php /var/www/html/occ app:enable twofactor_backupcodes' || true

# Install Audit Log for tracking user activity
echo "Installing Audit Log..."
su -s /bin/bash www-data -c 'php /var/www/html/occ app:install admin_audit' 2>/dev/null || true
su -s /bin/bash www-data -c 'php /var/www/html/occ app:enable admin_audit' || true

# Install Antivirus for Files (uses ClamAV daemon)
echo "Installing Antivirus for Files..."
su -s /bin/bash www-data -c 'php /var/www/html/occ app:install files_antivirus' 2>/dev/null || true
su -s /bin/bash www-data -c 'php /var/www/html/occ app:enable files_antivirus' || true
# Configure to use ClamAV daemon mode
echo "Configuring antivirus to use ClamAV daemon..."
su -s /bin/bash www-data -c 'php /var/www/html/occ config:app:set files_antivirus av_mode --value="daemon"' || true
su -s /bin/bash www-data -c 'php /var/www/html/occ config:app:set files_antivirus av_host --value="clamav"' || true
su -s /bin/bash www-data -c 'php /var/www/html/occ config:app:set files_antivirus av_port --value="3310"' || true
su -s /bin/bash www-data -c 'php /var/www/html/occ config:app:set files_antivirus av_stream_max_length --value="104857600"' || true
su -s /bin/bash www-data -c 'php /var/www/html/occ config:app:set files_antivirus av_infected_action --value="delete"' || true

# Run mimetype migration if not already done
MIGRATION_FLAG="/var/www/html/data/.mimetype-migration-done"
if [ ! -f "$MIGRATION_FLAG" ]; then
    echo "Running mimetype migrations..."
    su -s /bin/bash www-data -c 'php /var/www/html/occ maintenance:repair --include-expensive' || true
    touch "$MIGRATION_FLAG"
    chown www-data:www-data "$MIGRATION_FLAG"
fi

# Add missing database indices if not already done
INDICES_FLAG="/var/www/html/data/.db-indices-added"
if [ ! -f "$INDICES_FLAG" ]; then
    echo "Adding missing database indices..."
    su -s /bin/bash www-data -c 'php /var/www/html/occ db:add-missing-indices' || true
    touch "$INDICES_FLAG"
    chown www-data:www-data "$INDICES_FLAG"
fi

# Scan files to detect missing README files and update file cache
SCAN_FLAG="/var/www/html/data/.initial-scan-done"
if [ ! -f "$SCAN_FLAG" ]; then
    echo "Running initial file scan..."
    su -s /bin/bash www-data -c 'php /var/www/html/occ files:scan --all' || true
    touch "$SCAN_FLAG"
    chown www-data:www-data "$SCAN_FLAG"
fi

# Wait for the main process
wait $NEXTCLOUD_PID
