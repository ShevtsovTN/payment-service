FROM php:8.3-fpm-alpine

RUN apk add --no-cache \
        supervisor \
        curl \
        git \
        unzip \
        libpq \
        postgresql-dev \
        libzip-dev \
        zlib-dev \
        icu-dev \
        libpng-dev \
        libjpeg-turbo-dev \
        freetype-dev \
        oniguruma-dev \
    && apk add --no-cache --virtual .build-deps \
        $PHPIZE_DEPS \
    && docker-php-ext-configure gd \
        --with-freetype \
        --with-jpeg \
    && docker-php-ext-install \
        pdo \
        pdo_pgsql \
        pgsql \
        zip \
        gd \
        intl \
        mbstring \
        bcmath \
        opcache \
        pcntl \
    && pecl install redis \
    && docker-php-ext-enable redis \
    && apk del .build-deps

COPY --from=composer:latest /usr/bin/composer /usr/bin/composer

WORKDIR /var/www/html

COPY php-fpm.conf     /usr/local/etc/php-fpm.conf
COPY www.conf         /usr/local/etc/php-fpm.d/www.conf
COPY supervisord.conf /etc/supervisor/supervisord.conf
COPY worker.conf      /etc/supervisor/conf.d/worker.conf
COPY opcache.ini      /usr/local/etc/php/conf.d/opcache.ini

RUN mkdir -p \
        /var/log/supervisor \
        /var/run/supervisor \
        /var/log/php \
        /var/www/html/storage/app/public \
        /var/www/html/storage/framework/cache \
        /var/www/html/storage/framework/sessions \
        /var/www/html/storage/framework/views \
        /var/www/html/storage/logs \
        /var/www/html/bootstrap/cache \
    && chown -R www-data:www-data /var/www/html \
    && chown -R www-data:www-data /var/log/php

COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

EXPOSE 9000

ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["/usr/bin/supervisord", "-c", "/etc/supervisor/supervisord.conf"]