# ================================
# Stage 1: Node Builder - Compile Frontend Assets
# ================================
FROM node:20-alpine AS node-builder

WORKDIR /app

# Copy package files
COPY package*.json ./

# Install npm all dependencies
RUN npm ci

# Copy source files needed for asset compilation
COPY resources ./resources
COPY public ./public
COPY webpack.mix.js ./
COPY .env.example ./.env

# Build production assets
RUN npm run build

# ================================
# Stage 2: Composer Builder - Install PHP Dependencies
# ================================
FROM php:8.3-cli-alpine AS composer-builder

# Copy Composer binary from official Composer image
COPY --from=composer:latest /usr/bin/composer /usr/local/bin/composer

# Install required PHP extensions for composer dependencies
RUN apk add --no-cache \
    # Build dependencies for gd
    $PHPIZE_DEPS \
    libpng-dev \
    libjpeg-turbo-dev \
    freetype-dev \
    oniguruma \
    oniguruma-dev \
    libzip \
    libzip-dev \
    && docker-php-ext-configure gd \
        --with-freetype \
        --with-jpeg \
    && docker-php-ext-install -j$(nproc) \
        gd \
        pcntl \
        zip \
    # Clean up build dependencies to reduce layer size
    && apk del $PHPIZE_DEPS libpng-dev libjpeg-turbo-dev freetype-dev

WORKDIR /app

# Copy composer files
COPY composer.json composer.lock ./

# Install production dependencies
RUN composer install \
    --no-dev \
    --optimize-autoloader

# ================================
# Stage 3: PHP-FPM Runtime - Final Production Image
# ================================
FROM php:8.3-fpm-alpine

LABEL maintainer="BMAC Team"
LABEL description="Book me a Cookie - VATSIM Booking System"

# Set working directory
WORKDIR /var/www

# Install system dependencies
RUN apk add --no-cache \
    # Runtime dependencies
    mysql-client \
    icu-libs \
    libzip \
    libpng \
    libjpeg-turbo \
    freetype \
    oniguruma \
    # Build dependencies (will be removed later)
    $PHPIZE_DEPS \
    autoconf \
    g++ \
    make \
    libzip-dev \
    libpng-dev \
    libjpeg-turbo-dev \
    freetype-dev \
    icu-dev \
    oniguruma-dev

# Configure and install PHP extensions
RUN docker-php-ext-configure gd \
    --with-freetype \
    --with-jpeg \
    && docker-php-ext-install -j$(nproc) \
    pdo_mysql \
    mysqli \
    mbstring \
    xml \
    gd \
    zip \
    bcmath \
    pcntl \
    posix \
    intl \
    && pecl install redis \
    && docker-php-ext-enable redis opcache

# Remove build dependencies to reduce image size
RUN apk del $PHPIZE_DEPS autoconf g++ make libzip-dev libpng-dev libjpeg-turbo-dev freetype-dev icu-dev oniguruma-dev \
    && rm -rf /tmp/* /var/cache/apk/*

# Copy OPcache configuration
COPY docker/php/opcache.ini /usr/local/etc/php/conf.d/opcache.ini

# Copy PHP-FPM pool configuration (optional customization)
RUN echo "pm = dynamic" >> /usr/local/etc/php-fpm.d/www.conf \
    && echo "pm.max_children = 50" >> /usr/local/etc/php-fpm.d/www.conf \
    && echo "pm.start_servers = 5" >> /usr/local/etc/php-fpm.d/www.conf \
    && echo "pm.min_spare_servers = 5" >> /usr/local/etc/php-fpm.d/www.conf \
    && echo "pm.max_spare_servers = 35" >> /usr/local/etc/php-fpm.d/www.conf

# Copy application source
COPY --chown=www-data:www-data . /var/www

# Copy vendor from composer stage
COPY --from=composer-builder --chown=www-data:www-data /app/vendor /var/www/vendor

# Copy compiled assets from node stage
COPY --from=node-builder --chown=www-data:www-data /app/public/js /var/www/public/js
COPY --from=node-builder --chown=www-data:www-data /app/public/css /var/www/public/css
COPY --from=node-builder --chown=www-data:www-data /app/public/mix-manifest.json /var/www/public/mix-manifest.json

# Create required directories and set permissions
RUN mkdir -p \
    storage/framework/cache \
    storage/framework/sessions \
    storage/framework/views \
    storage/logs \
    bootstrap/cache \
    && chmod -R 775 storage bootstrap/cache \
    && chown -R www-data:www-data storage bootstrap/cache

# Copy entrypoint script
COPY docker/entrypoint.sh /docker-entrypoint.sh
RUN chmod +x /docker-entrypoint.sh

# Switch to non-root user
USER www-data

# Expose PHP-FPM port
EXPOSE 9000

# Set entrypoint
ENTRYPOINT ["/docker-entrypoint.sh"]

# Default command (can be overridden by CONTAINER_ROLE)
CMD ["app"]
