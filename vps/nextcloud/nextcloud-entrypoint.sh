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

# Apply configuration (apps, settings, integrations)
bash /custom-configure.sh

# Wait for the main process
wait $NEXTCLOUD_PID
