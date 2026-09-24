# syntax=docker/dockerfile:1.7
#
# Production image for BMAC: a single container running Caddy (plain HTTP on
# :8080), php-fpm, the queue worker and the scheduler under supervisord.
# TLS is expected to be terminated by an upstream reverse proxy.
#
# See docker/bin/docker-entrypoint and docker/supervisor/supervisord.conf.

ARG PHP_VERSION=8.5
ARG NODE_VERSION=22
ARG CADDY_VERSION=2

FROM caddy:${CADDY_VERSION}-alpine AS caddy

FROM composer:2 AS composer

# ---------------------------------------------------------------------------
# PHP runtime with the extensions required by Laravel, Horizon and
# spatie/simple-excel.
# ---------------------------------------------------------------------------
FROM php:${PHP_VERSION}-fpm-alpine AS php-base

COPY --from=mlocati/php-extension-installer:2 /usr/bin/install-php-extensions /usr/local/bin/

RUN set -eux; \
    apk add --no-cache supervisor tini; \
    install-php-extensions \
        bcmath \
        exif \
        gd \
        intl \
        opcache \
        pcntl \
        pdo_mysql \
        pdo_pgsql \
        redis \
        zip; \
    rm /usr/local/bin/install-php-extensions

# ---------------------------------------------------------------------------
# Composer dependencies (production only).
# ---------------------------------------------------------------------------
FROM php-base AS vendor

COPY --from=composer /usr/bin/composer /usr/local/bin/composer

WORKDIR /app

COPY composer.json composer.lock ./

RUN --mount=type=cache,target=/root/.composer/cache \
    composer install \
        --no-dev \
        --no-scripts \
        --no-autoloader \
        --no-interaction \
        --no-progress \
        --prefer-dist

# ---------------------------------------------------------------------------
# Frontend assets. Bootstrap colours are compiled into the CSS, so they are
# build arguments rather than runtime settings.
# ---------------------------------------------------------------------------
FROM node:${NODE_VERSION}-alpine AS assets

WORKDIR /app

COPY package.json package-lock.json ./

RUN --mount=type=cache,target=/root/.npm \
    npm ci --no-audit --no-fund

COPY vite.config.js ./
COPY resources ./resources
# PurgeCSS scans the Laravel pagination views.
COPY --from=vendor /app/vendor/laravel/framework/src/Illuminate/Pagination/resources/views \
    ./vendor/laravel/framework/src/Illuminate/Pagination/resources/views

ARG BOOTSTRAP_COLOR_PRIMARY="#2C3E50"
ARG BOOTSTRAP_COLOR_SECONDARY="#95a5a6"
ARG BOOTSTRAP_COLOR_TERTIARY="#18BC9C"
ARG BOOTSTRAP_COLOR_SUCCESS="#18BC9C"
ARG BOOTSTRAP_COLOR_DANGER="#E74C3C"
ARG BOOTSTRAP_COLOR_WARNING="#F39C12"

RUN npm run build

# ---------------------------------------------------------------------------
# Application source + optimized autoloader.
# ---------------------------------------------------------------------------
FROM php-base AS build

COPY --from=composer /usr/bin/composer /usr/local/bin/composer

WORKDIR /var/www/html

COPY --from=vendor /app/vendor ./vendor
COPY . .
COPY --from=assets /app/public/build ./public/build

RUN set -eux; \
    composer dump-autoload --optimize --no-dev --no-interaction; \
    ln -s ../storage/app/public public/storage; \
    rm -rf docker Dockerfile .dockerignore

# ---------------------------------------------------------------------------
# Runtime image.
# ---------------------------------------------------------------------------
FROM php-base AS app

LABEL org.opencontainers.image.title="BMAC" \
      org.opencontainers.image.description="Book me a Cookie - VATSIM event booking system (Caddy + php-fpm)" \
      org.opencontainers.image.source="https://github.com/herver/vaccfr-bmac" \
      org.opencontainers.image.licenses="MIT"

ENV APP_ENV=production \
    APP_DEBUG=false \
    LOG_CHANNEL=stderr \
    LOG_LEVEL=info \
    CADDY_PORT=8080 \
    QUEUE_ENABLED=true \
    QUEUE_STOP_WAIT=60 \
    SCHEDULER_ENABLED=true \
    SUPERVISOR_LOG_LEVEL=info \
    XDG_CONFIG_HOME=/tmp/caddy/config \
    XDG_DATA_HOME=/tmp/caddy/data \
    PHP_MEMORY_LIMIT=256M \
    PHP_MAX_EXECUTION_TIME=120 \
    PHP_UPLOAD_MAX_FILESIZE=20M \
    PHP_POST_MAX_SIZE=25M \
    PHP_OPCACHE_MEMORY=128 \
    PHP_OPCACHE_VALIDATE_TIMESTAMPS=0 \
    PHP_FPM_PM=dynamic \
    PHP_FPM_MAX_CHILDREN=20 \
    PHP_FPM_START_SERVERS=4 \
    PHP_FPM_MIN_SPARE_SERVERS=2 \
    PHP_FPM_MAX_SPARE_SERVERS=6 \
    PHP_FPM_MAX_REQUESTS=500

COPY --from=caddy /usr/bin/caddy /usr/local/bin/caddy

COPY docker/caddy/Caddyfile /etc/caddy/Caddyfile
COPY docker/php/php.ini /usr/local/etc/php/conf.d/zz-bmac.ini
COPY docker/php/php-fpm.conf /usr/local/etc/php-fpm.d/zz-docker.conf
COPY docker/supervisor/supervisord.conf /etc/supervisord.conf
COPY docker/bin/ /usr/local/bin/

WORKDIR /var/www/html

# Application code is owned by root and read-only for the runtime user; only
# storage/ and bootstrap/cache/ are writable.
COPY --from=build /var/www/html /var/www/html

RUN set -eux; \
    rm -f /usr/local/etc/php-fpm.d/www.conf.default; \
    sed -i -e '/^user = /d' -e '/^group = /d' /usr/local/etc/php-fpm.d/www.conf; \
    chown -R www-data:www-data storage bootstrap/cache; \
    php -m | grep -qi 'zend opcache'; \
    caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile; \
    rm -rf /tmp/caddy

USER www-data

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=10s --start-period=90s --retries=3 \
    CMD ["docker-healthcheck"]

ENTRYPOINT ["/sbin/tini", "--", "docker-entrypoint"]
CMD ["supervisord"]
