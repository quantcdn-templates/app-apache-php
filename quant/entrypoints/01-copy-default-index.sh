#!/bin/bash

# Copy default index.php if no index file exists in /var/www/html/
# This helps when users mount their own code but don't have an index file yet

echo "Checking for index file in /var/www/html/..."

# Check for common index file patterns
if [ ! -f /var/www/html/index.php ] && \
   [ ! -f /var/www/html/index.html ] && \
   [ ! -f /var/www/html/index.htm ]; then
    
    echo "No index file found, copying default index.php..."
    
    # Ensure the default source directory exists
    if [ -f /opt/default-src/index.php ]; then
        cp /opt/default-src/index.php /var/www/html/index.php
        chown www-data:www-data /var/www/html/index.php
        chmod 644 /var/www/html/index.php
        echo "✅ Default index.php copied to /var/www/html/"
    else
        echo "⚠️  No default index.php found in /opt/default-src/"
    fi
else
    echo "✅ Index file already exists, skipping default copy"
fi