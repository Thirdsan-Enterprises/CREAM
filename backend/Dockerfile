FROM php:8.4-fpm-alpine AS base

RUN apk add --no-cache \
    bash \
    curl \
    git \
    icu-dev \
    libzip-dev \
    oniguruma-dev \
    zip \
    unzip \
    nginx \
    supervisor \
    && docker-php-ext-install \
    bcmath \
    intl \
    pdo_mysql \
    zip \
    opcache

COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

WORKDIR /var/www/html

COPY composer.json composer.lock ./
RUN composer install --no-dev --no-interaction --no-progress --no-scripts --prefer-dist

COPY . .
RUN composer dump-autoload --optimize --no-dev

COPY docker/nginx.conf /etc/nginx/nginx.conf
COPY docker/supervisord.conf /etc/supervisor/conf.d/supervisord.conf
COPY docker/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

RUN chown -R www-data:www-data /var/www/html/storage /var/www/html/bootstrap/cache

EXPOSE 8080

ENTRYPOINT ["/entrypoint.sh"]
CMD ["/usr/bin/supervisord", "-c", "/etc/supervisor/conf.d/supervisord.conf"]
