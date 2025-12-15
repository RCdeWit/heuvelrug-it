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
su -s /bin/bash www-data -c 'php /var/www/html/occ config:system:set skeletondirectory --value=""' || true

# Configure local cache (APCu)
# Note: Redis distributed cache and locking are configured automatically by the Docker image
# via REDIS_HOST and REDIS_HOST_PASSWORD environment variables
# See: https://github.com/nextcloud/docker/blob/master/.config/redis.config.php
echo "Configuring local cache..."
su -s /bin/bash www-data -c 'php /var/www/html/occ config:system:set memcache.local --value="\\OC\\Memcache\\APCu"' || true

# Additional performance settings
echo "Applying performance settings..."
su -s /bin/bash www-data -c 'php /var/www/html/occ config:system:set filelocking.enabled --value=true --type=boolean' || true
su -s /bin/bash www-data -c 'php /var/www/html/occ config:system:set log_query --value=false --type=boolean' || true
su -s /bin/bash www-data -c 'php /var/www/html/occ config:system:set loglevel --value=2 --type=integer' || true

# Note: SMTP configuration is handled automatically by the Nextcloud Docker image
# using the SMTP_HOST, SMTP_PORT, SMTP_SECURE, SMTP_AUTHTYPE, SMTP_NAME, SMTP_PASSWORD,
# MAIL_FROM_ADDRESS, and MAIL_DOMAIN environment variables.
# See: https://github.com/nextcloud/docker/blob/master/.config/smtp.config.php

# Set up cron job for background tasks
echo "Setting up cron for background jobs..."
# Install cron if not present
apt-get update -qq && apt-get install -y -qq cron > /dev/null 2>&1 || true
# Set up crontab for www-data user
echo "*/5 * * * * php -f /var/www/html/cron.php" | crontab -u www-data -
# Start cron daemon in background (must run continuously)
cron
echo "Cron daemon started for background jobs"

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
su -s /bin/bash www-data -c 'php /var/www/html/occ config:app:set richdocuments wopi_url --value=https://office.dobbertjeduik.nl' || true
su -s /bin/bash www-data -c 'php /var/www/html/occ config:app:set richdocuments public_wopi_url --value=https://office.dobbertjeduik.nl' || true
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

# Wait for the main process
wait $NEXTCLOUD_PID
