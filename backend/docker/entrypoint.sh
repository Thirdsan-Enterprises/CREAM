#!/bin/bash
set -e

if [ ! -f /var/www/html/.env ]; then
    cp /var/www/html/.env.example /var/www/html/.env
fi

php artisan config:cache
php artisan route:cache
php artisan migrate --force

exec "$@"
