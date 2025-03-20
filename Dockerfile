# Use PHP 7.1 with FPM on Alpine
FROM php:7.1-fpm-alpine
# Set working directory
WORKDIR /var/www/html
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

# Create a non-root user
RUN addgroup -g 1000 symfony && adduser -G symfony -u 1000 -D symfony

# Copy application files
COPY . .

# Ensure var/cache and var/log directories exist with correct permissions
RUN mkdir -p app/cache app/logs \
    && chown -R symfony:symfony /var/www/html \
    && chmod -R 775 /var/www/html

# Create directories for nginx and logs
RUN mkdir -p /run/nginx /var/log/nginx \
    && chown -R nginx:nginx /run/nginx /var/log/nginx

# Modify AppKernel.php to conditionally load SensioGeneratorBundle only in dev environment
RUN sed -i "s/new Sensio\\\\Bundle\\\\GeneratorBundle\\\\SensioGeneratorBundle(),/\$this->environment === 'dev' ? new Sensio\\\\Bundle\\\\GeneratorBundle\\\\SensioGeneratorBundle() : null,/" app/AppKernel.php \
    && sed -i '/null,/s/,\s*null,/,/' app/AppKernel.php

# Switch to non-root user
USER symfony

# Install Symfony dependencies (including dev dependencies)
RUN COMPOSER_MEMORY_LIMIT=-1 composer install --optimize-autoloader

# Clear cache for production
RUN php app/console cache:clear --env=prod --no-debug

# Switch back to root user for supervisor and nginx
USER root

# Create NGINX configuration
RUN echo " \
user nginx; \
worker_processes auto; \
pid /run/nginx/nginx.pid; \
error_log /var/log/nginx/error.log warn; \
\
events { worker_connections 1024; } \
\
http { \
    include /etc/nginx/mime.types; \
    default_type application/octet-stream; \
    sendfile on; \
    keepalive_timeout 65; \
    \
    server { \
        listen 80; \
        server_name _; \
        root /var/www/html/web; \
        \
        location / { \
            try_files \$uri /app.php\$is_args\$args; \
        } \
        \
        location ~ ^/app\\.php(/|$) { \
            fastcgi_pass 127.0.0.1:9000; \
            fastcgi_split_path_info ^(.+\\.php)(/.*)$; \
            include fastcgi_params; \
            fastcgi_param SCRIPT_FILENAME \$realpath_root\$fastcgi_script_name; \
            fastcgi_param DOCUMENT_ROOT \$realpath_root; \
            internal; \
        } \
        \
        location ~ \\.php$ { \
            return 404; \
        } \
        \
        error_log /var/log/nginx/error.log; \
        access_log /var/log/nginx/access.log; \
    } \
}" > /etc/nginx/nginx.conf

# Create single supervisord.conf file with proper content
RUN echo "[supervisord]" > /etc/supervisord.conf && \
    echo "nodaemon=true" >> /etc/supervisord.conf && \
    echo "" >> /etc/supervisord.conf && \
    echo "[program:php-fpm]" >> /etc/supervisord.conf && \
    echo "command=docker-php-entrypoint php-fpm" >> /etc/supervisord.conf && \
    echo "autostart=true" >> /etc/supervisord.conf && \
    echo "autorestart=true" >> /etc/supervisord.conf && \
    echo "stderr_logfile=/var/log/php-fpm.err.log" >> /etc/supervisord.conf && \
    echo "stdout_logfile=/var/log/php-fpm.out.log" >> /etc/supervisord.conf && \
    echo "" >> /etc/supervisord.conf && \
    echo "[program:nginx]" >> /etc/supervisord.conf && \
    echo "command=nginx -g 'daemon off;'" >> /etc/supervisord.conf && \
    echo "autostart=true" >> /etc/supervisord.conf && \
    echo "autorestart=true" >> /etc/supervisord.conf && \
    echo "stderr_logfile=/var/log/nginx.err.log" >> /etc/supervisord.conf && \
    echo "stdout_logfile=/var/log/nginx.out.log" >> /etc/supervisord.conf

# Expose port 80
EXPOSE 80
# Start Supervisor to run both NGINX & PHP-FPM
CMD ["/usr/bin/supervisord", "-c", "/etc/supervisord.conf"]
