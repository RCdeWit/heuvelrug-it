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

# Apply custom configuration settings
echo "Applying custom configuration..."
su -s /bin/bash www-data -c 'php /var/www/html/occ config:system:set trusted_proxies 0 --value="172.16.0.0/12"' || true
su -s /bin/bash www-data -c 'php /var/www/html/occ config:system:set forwarded_for_headers 0 --value="HTTP_X_FORWARDED_FOR"' || true
su -s /bin/bash www-data -c 'php /var/www/html/occ config:system:set maintenance_window_start --value=2 --type=integer' || true
su -s /bin/bash www-data -c 'php /var/www/html/occ config:system:set default_phone_region --value="NL"' || true
su -s /bin/bash www-data -c 'php /var/www/html/occ config:system:set backgroundjobs_mode --value="cron"' || true

# Set up cron job for background tasks
echo "Setting up cron for background jobs..."
echo "*/5 * * * * php -f /var/www/html/cron.php" | crontab -u www-data -
service cron start || true

# Disable AppAPI
echo "Disabling AppAPI..."
su -s /bin/bash www-data -c 'php /var/www/html/occ app:disable app_api' 2>/dev/null || true

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

# Wait for the main process
wait $NEXTCLOUD_PID
