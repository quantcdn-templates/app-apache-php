ARG PHP_VERSION=8.4
ARG DEBIAN_VERSION=trixie
# Use trixie for PHP 8.2+, bullseye for PHP 7.4 (since trixie/bookworm not available)
FROM php:${PHP_VERSION}-apache-${DEBIAN_VERSION}

# Update system packages for security
RUN set -ex; \
    apt-get update && \
    apt-get upgrade -y && \
    apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        default-mysql-client \
        gettext \
        ghostscript \
        git \
        gosu \
        libfreetype6-dev \
        libicu-dev \
        libjpeg-dev \
        libmagickwand-dev \
        libpng-dev \
        libpq-dev \
        libwebp-dev \
        libzip-dev \
        openssl \
        sudo \
        unzip \
        vim \
    && \
    # Install AVIF headers only for PHP >= 8.1 where we enable AVIF in GD (allow failure on unsupported arches/repos)
    if php -r 'exit(PHP_VERSION_ID >= 80100 ? 0 : 1);'; then \
        apt-get install -y --no-install-recommends libavif-dev || echo "libavif-dev not available; continuing without AVIF"; \
    fi; \
    \
    # Configure and install PHP extensions
    if php -r 'exit(PHP_VERSION_ID >= 80100 ? 0 : 1);' && dpkg -s libavif-dev >/dev/null 2>&1; then \
        GD_CONFIGURE_OPTIONS="--with-avif --with-freetype --with-jpeg=/usr --with-webp"; \
    else \
        GD_CONFIGURE_OPTIONS="--with-freetype --with-jpeg=/usr --with-webp"; \
    fi; \
    docker-php-ext-configure gd $GD_CONFIGURE_OPTIONS \
    && \
    docker-php-ext-install -j "$(nproc)" \
        bcmath \
        exif \
        gd \
        intl \
        mysqli \
        opcache \
        pdo_mysql \
        pdo_pgsql \
        sockets \
        zip \
    && \
    # Install PECL extensions (pin imagick on older PHP)
    if php -r 'exit(PHP_VERSION_ID < 80000 ? 0 : 1);'; then \
        pecl install -o -f apcu imagick-3.7.0 redis; \
    else \
        pecl install -o -f apcu imagick redis; \
    fi; \
    docker-php-ext-enable apcu imagick redis && \
    rm -rf /tmp/pear && \
    # Install AWS RDS CA certificates
    mkdir -p /tmp/rds-certs && \
    curl -fsSL "https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem" \
         -o /tmp/rds-certs/rds-ca-cert-bundle.pem && \
    mkdir -p /opt/rds-ca-certs && \
    cp /tmp/rds-certs/rds-ca-cert-bundle.pem /opt/rds-ca-certs/rds-ca-cert-bundle.pem && \
    cp /tmp/rds-certs/rds-ca-cert-bundle.pem /usr/local/share/ca-certificates/rds-ca-cert-bundle.crt && \
    update-ca-certificates && \
    rm -rf /tmp/rds-certs && \
    echo "RDS CA certificates installed successfully" && \
    # Clean up
    rm -rf /var/lib/apt/lists/* && \
    # Enable Apache modules
    a2enmod expires headers remoteip rewrite && \
    # Add Quant-Client-IP header to existing remoteip configuration
    echo 'RemoteIPHeader Quant-Client-IP' >> /etc/apache2/conf-available/remoteip.conf && \
    a2enconf remoteip && \
    # Verify extensions work correctly
    out="$(php -r 'exit(0);')"; \
    [ -z "$out" ]; \
    err="$(php -r 'exit(0);' 3>&1 1>&2 2>&3)"; \
    [ -z "$err" ]; \
    \
    extDir="$(php -r 'echo ini_get("extension_dir");')"; \
    [ -d "$extDir" ]; \
    # Clean up build dependencies
    savedAptMark="$(apt-mark showmanual)"; \
    apt-mark auto '.*' > /dev/null; \
    if [ -n "$savedAptMark" ]; then apt-mark manual $savedAptMark; fi; \
    ldd "$extDir"/*.so \
      | awk '/=>/ { so = $(NF-1); if (index(so, "/usr/local/") == 1) { next }; gsub("^/(usr/)?", "", so); printf "*%s\n", so }' \
      | sort -u \
      | xargs -r dpkg-query --search \
      | cut -d: -f1 \
      | sort -u \
      | xargs -rt apt-mark manual; \
    \
    apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false || true; \
    rm -rf /var/lib/apt/lists/*; \
    \
    ! { ldd "$extDir"/*.so | grep 'not found'; }; \
    # Check for PHP extension loading errors
    err="$(php --version 3>&1 1>&2 2>&3)"; \
    [ -z "$err" ]

# Remap www-data to UID/GID 1000 to match EFS access points
RUN groupmod -g 1000 www-data && \
    usermod -u 1000 -g 1000 www-data && \
    # Fix ownership of existing www-data files after UID/GID change
    find / -user 33 -exec chown www-data {} \; 2>/dev/null || true && \
    find / -group 33 -exec chgrp www-data {} \; 2>/dev/null || true && \
    # Configure Apache to log to stdout/stderr 
    sed -i 's/ErrorLog .*/ErrorLog \/dev\/stderr/' /etc/apache2/apache2.conf && \
    sed -i 's/CustomLog .*/CustomLog \/dev\/stdout combined/' /etc/apache2/sites-available/000-default.conf && \
    sed -i 's!ErrorLog.*!ErrorLog /dev/stderr!' /etc/apache2/sites-available/000-default.conf && \
    # Disable the other-vhosts-access-log configuration that causes permission issues
    a2disconf other-vhosts-access-log || true && \
    # Ensure Apache run directory exists and has correct permissions
    mkdir -p /var/run/apache2 && \
    chown -R www-data:www-data /var/run/apache2

# PHP configuration is handled via quant/php.ini.d/ files:
# - 96-memory.ini - Memory limits
# - 97-opcache.ini - OPcache configuration
# - 98-upload-limits.ini - Upload/POST limits  
# - 99-quant-logging.ini - Error reporting and logging

# Fix LogFormat for proper client IP logging
RUN find /etc/apache2 -type f -name '*.conf' -exec sed -ri 's/([[:space:]]*LogFormat[[:space:]]+"[^"]*)%h([^"]*")/\1%a\2/g' '{}' +

# Quant Host header override (VirtualHost include approach)
RUN cat <<'EOF' > /etc/apache2/conf-available/quant-host-snippet.conf
<IfModule mod_rewrite.c>
    RewriteEngine On
    # Priority 1: Check HTTP header Quant-Orig-Host (only accept well-formed hosts)
    RewriteCond %{HTTP:Quant-Orig-Host} ^([A-Za-z0-9.-]+(?::[0-9]+)?)$ [NC]
    RewriteRule ^ - [E=QUANT_HOST:%1]
    # Priority 2: If header not set, check env var QUANT_ORIG_HOST
    RewriteCond %{ENV:QUANT_HOST} ^$
    RewriteCond %{ENV:QUANT_ORIG_HOST} ^([A-Za-z0-9.-]+(?::[0-9]+)?)$ [NC]
    RewriteRule ^ - [E=QUANT_HOST:%1]
</IfModule>
# Only override Host header if QUANT_HOST was set by one of the rules above
RequestHeader set Host "%{QUANT_HOST}e" env=QUANT_HOST
EOF

RUN a2enconf quant-host-snippet

RUN sed -i '/DocumentRoot \/var\/www\/html/a\\n\t# Quant Host header override\n\tIncludeOptional /etc/apache2/conf-enabled/quant-host-snippet.conf' /etc/apache2/sites-available/000-default.conf

# Install Composer for PHP dependency management
COPY --from=composer:2 /usr/bin/composer /usr/local/bin/

# Include Quant config include (includes document root configuration)
COPY quant/entrypoints/ /quant-entrypoint.d/
RUN chmod +x /quant-entrypoint.d/*

# Copy custom entrypoint for local development testing
COPY quant/docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

# Copy Quant PHP configuration files (allows users to add custom PHP configs)
COPY quant/php.ini.d/* /usr/local/etc/php/conf.d/

# Set working directory
WORKDIR /var/www/html

# Copy default source files to template location (for copying when /var/www/html is mounted)
COPY src/ /opt/default-src/

# Copy application source code
COPY src/ /var/www/html/

# Set proper permissions
RUN chown -R www-data:www-data /var/www/html

# Expose port
EXPOSE 80

# Use Quant entrypoints with standard Apache entrypoint
ENTRYPOINT ["docker-php-entrypoint"]
CMD ["apache2-foreground"] 
