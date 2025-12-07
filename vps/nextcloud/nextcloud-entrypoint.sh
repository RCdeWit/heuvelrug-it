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
