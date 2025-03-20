# Use PHP 7.1 with FPM on Alpine
FROM php:7.1-fpm-alpine

# Install system dependencies and required PHP extensions
RUN apk update && apk add --no-cache \
    nginx \
    supervisor \
    git \
    unzip \
    libpng \
    libpng-dev \
    freetype \
    freetype-dev \
    libjpeg-turbo \
    libjpeg-turbo-dev \
    icu \
    icu-dev \
    postgresql-dev \
    mariadb-client \
    mariadb-connector-c-dev \
    && docker-php-ext-configure gd --with-freetype-dir=/usr/include/ --with-jpeg-dir=/usr/include/ \
    && docker-php-ext-install pdo pdo_mysql pdo_pgsql gd intl \
    && docker-php-ext-enable opcache

# Install Composer
COPY --from=composer:1 /usr/bin/composer /usr/bin/composer

# Set working directory
WORKDIR /var/www/html

# Copy application files
COPY . .

# Modify AppKernel.php to conditionally load SensioGeneratorBundle only in dev environment
RUN sed -i "s/new Sensio\\\\Bundle\\\\GeneratorBundle\\\\SensioGeneratorBundle(),/\$this->environment === 'dev' ? new Sensio\\\\Bundle\\\\GeneratorBundle\\\\SensioGeneratorBundle() : null,/" app/AppKernel.php \
    && sed -i '/null,/s/,\s*null,/,/' app/AppKernel.php

# Ensure cache and log directories exist with very permissive permissions
RUN mkdir -p app/cache/prod app/cache/dev app/logs \
    && chmod -R 777 app/cache app/logs

# Install Symfony dependencies (including dev dependencies) with increased memory limit
RUN COMPOSER_MEMORY_LIMIT=-1 composer install --optimize-autoloader

# Configure PHP-FPM
COPY <<EOF /usr/local/etc/php-fpm.d/www.conf
[www]
user = www-data
group = www-data
listen = 127.0.0.1:9000
pm = dynamic
pm.max_children = 5
pm.start_servers = 2
pm.min_spare_servers = 1
pm.max_spare_servers = 3
EOF

# Create NGINX configuration file
COPY <<EOF /etc/nginx/nginx.conf
user www-data;
worker_processes auto;
error_log /var/log/nginx/error.log warn;
pid /var/run/nginx.pid;

events {
    worker_connections 1024;
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;
    sendfile on;
    access_log /var/log/nginx/access.log;
    keepalive_timeout 65;

    server {
        listen 80 default_server;
        server_name _;
        root /var/www/html/web;

        location / {
            try_files \$uri /app.php\$is_args\$args;
        }

        location ~ ^/app\\.php(/|$) {
            fastcgi_pass 127.0.0.1:9000;
            fastcgi_split_path_info ^(.+\\.php)(/.*)$;
            include fastcgi_params;
            fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
            fastcgi_param HTTPS off;
        }

        error_log /var/log/nginx/project_error.log;
        access_log /var/log/nginx/project_access.log;
    }
}
EOF

# Create supervisord configuration
COPY <<EOF /etc/supervisord.conf
[supervisord]
nodaemon=true
logfile=/var/log/supervisord.log
pidfile=/var/run/supervisord.pid

[program:php-fpm]
command=php-fpm -F
autostart=true
autorestart=true
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile=/dev/stderr
stderr_logfile_maxbytes=0

[program:nginx]
command=nginx -g 'daemon off;'
autostart=true
autorestart=true
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile=/dev/stderr
stderr_logfile_maxbytes=0
EOF

# Create necessary directories with proper permissions
RUN mkdir -p /var/log/nginx /var/run \
    && touch /var/run/nginx.pid \
    && chown -R www-data:www-data /var/log/nginx /var/run/nginx.pid \
    && chmod -R 777 app/cache app/logs

# Verify the nginx configuration is valid
RUN nginx -t

# Clear Symfony cache in production
RUN php app/console cache:clear --env=prod --no-debug || true

# Make everything writable after cache clear just to be sure
RUN chmod -R 777 app/cache app/logs

# Expose port 80
EXPOSE 80

# Start supervisor
CMD ["/usr/bin/supervisord", "-c", "/etc/supervisord.conf"]
