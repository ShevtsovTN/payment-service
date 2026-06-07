#!/bin/sh
set -e

chown -R www-data:www-data /var/www/html/storage
chown -R www-data:www-data /var/www/html/bootstrap/cache

if [ -f "artisan" ]; then
    php artisan config:cache
    php artisan route:cache
    php artisan view:cache
    php artisan migrate --force
fi

exec "$@"