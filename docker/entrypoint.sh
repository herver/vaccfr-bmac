#!/bin/sh
set -e

echo "============================================"
echo "BMAC Laravel Application - Starting..."
echo "Container Role: ${CONTAINER_ROLE:-app}"
echo "============================================"

# Ensure proper permissions for storage and cache directories
echo "Setting permissions for storage and cache directories..."
chmod -R 775 /var/www/storage /var/www/bootstrap/cache 2>/dev/null || true
chown -R www-data:www-data /var/www/storage /var/www/bootstrap/cache 2>/dev/null || true

# Cache warming for improved performance
# Only run for app containers to avoid redundant caching in queue/scheduler
if [ "${CONTAINER_ROLE}" = "app" ]; then
    echo "Warming Laravel caches..."
    php artisan config:cache
    php artisan route:cache
    php artisan view:cache
fi

# Route to appropriate service based on CONTAINER_ROLE
case "${CONTAINER_ROLE}" in
    "app")
        echo "Starting PHP-FPM server..."
        exec php-fpm
        ;;

    "scheduler")
        echo "Starting Laravel Scheduler (runs every minute)..."
        # Laravel 10+ supports schedule:work for long-running scheduler process
        exec php artisan schedule:work
        ;;

    "horizon")
        echo "Starting Laravel Horizon queue worker..."
        # Horizon manages its own worker pool based on config/horizon.php
        exec php artisan horizon
        ;;

    "queue")
        echo "Starting generic queue worker..."
        # Fallback for non-Redis queue connections
        exec php artisan queue:work \
            --sleep=3 \
            --tries=3 \
            --timeout=90 \
            --max-jobs=1000 \
            --max-time=3600
        ;;

    *)
        echo "ERROR: CONTAINER_ROLE not set or invalid!"
        echo "Valid roles: app, scheduler, horizon, queue"
        echo "Current value: ${CONTAINER_ROLE}"
        exit 1
        ;;
esac
