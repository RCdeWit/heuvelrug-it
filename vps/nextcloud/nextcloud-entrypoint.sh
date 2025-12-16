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

# Disable AppAPI
echo "Disabling AppAPI..."
su -s /bin/bash www-data -c 'php /var/www/html/occ app:disable app_api' 2>/dev/null || true

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
