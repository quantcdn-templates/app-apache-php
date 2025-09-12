ARG PHP_VERSION=8.4
ARG DEBIAN_VERSION=trixie
# Use trixie for PHP 8.2+, bullseye for PHP 7.4 (since trixie/bookworm not available)
FROM php:${PHP_VERSION}-apache-${DEBIAN_VERSION}

# Update system packages for security
RUN apt-get update && apt-get upgrade -y && \
    apt-get install -y --no-install-recommends \
        ca-certificates \
        openssl \
        curl \
        sudo \
        gosu \
        vim \
        git \
        unzip \
        libfreetype6-dev \
        libjpeg-dev \
        libpng-dev \
        libpq-dev \
        libwebp-dev \
        libzip-dev \
        default-mysql-client \
    && \
    # Configure and install PHP extensions
    docker-php-ext-configure gd \
        --with-freetype \
        --with-jpeg=/usr \
        --with-webp \
    && \
    docker-php-ext-install -j "$(nproc)" \
        gd \
        opcache \
        pdo_mysql \
        pdo_pgsql \
        zip \
        sockets \
        bcmath \
    && \
    # Install PECL extensions  
    pecl install -o -f redis apcu && \
    docker-php-ext-enable redis apcu && \
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
    a2enmod rewrite headers remoteip && \
    # Add Quant-Client-IP header to existing remoteip configuration
    echo 'RemoteIPHeader Quant-Client-IP' >> /etc/apache2/conf-available/remoteip.conf && \
    a2enconf remoteip

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



# Set PHP configuration
RUN { \
        echo 'opcache.memory_consumption=300'; \
        echo 'opcache.interned_strings_buffer=8'; \
        echo 'opcache.max_accelerated_files=30000'; \
        echo 'opcache.revalidate_freq=60'; \
    } > /usr/local/etc/php/conf.d/opcache-recommended.ini && \
    echo 'memory_limit = 256M' >> /usr/local/etc/php/conf.d/docker-php-memlimit.ini

# Quant Host header override (VirtualHost include approach)
RUN cat <<'EOF' > /etc/apache2/conf-available/quant-host-snippet.conf
<IfModule mod_rewrite.c>
    RewriteEngine On
    # Only accept well-formed hosts (optional port)
    RewriteCond %{HTTP:Quant-Orig-Host} ^([A-Za-z0-9.-]+(?::[0-9]+)?)$ [NC]
    RewriteRule ^ - [E=QUANT_HOST:%1]
</IfModule>
RequestHeader set Host "%{QUANT_HOST}e" env=QUANT_HOST
EOF

RUN a2enconf quant-host-snippet

RUN sed -i '/DocumentRoot \/var\/www\/html/a\\n\t# Quant Host header override\n\tIncludeOptional /etc/apache2/conf-enabled/quant-host-snippet.conf' /etc/apache2/sites-available/000-default.conf

# Install Composer for PHP dependency management
COPY --from=composer:2 /usr/bin/composer /usr/local/bin/

# Include Quant config include
COPY quant/entrypoints/ /quant-entrypoint.d/
RUN chmod +x /quant-entrypoint.d/*

# Copy Quant PHP configuration files (allows users to add custom PHP configs)
COPY quant/php.ini.d/* /usr/local/etc/php/conf.d/

# Set working directory
WORKDIR /var/www/html

# Copy application source code
COPY src/ /var/www/html/

# Set proper permissions
RUN chown -R www-data:www-data /var/www/html

# Expose port
EXPOSE 80

# Use Quant entrypoints with standard Apache entrypoint
ENTRYPOINT ["docker-php-entrypoint"]
CMD ["apache2-foreground"] 
