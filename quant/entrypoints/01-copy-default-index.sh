#!/bin/bash

# Copy default index.php if no index file exists in document root
# This helps when users mount their own code but don't have an index file yet
# Set COPY_DEFAULT_INDEX=true to enable this behavior

# Skip if not explicitly enabled (allows derived images to disable this)
if [ "$COPY_DEFAULT_INDEX" != "true" ]; then
    echo "Default index copy disabled (set COPY_DEFAULT_INDEX=true to enable)"
    exit 0
fi

# Determine document root (use env var or default to /var/www/html)
DOC_ROOT="${DOCUMENT_ROOT:-/var/www/html}"

echo "Checking for index file in $DOC_ROOT..."

# Check for common index file patterns
if [ ! -f "$DOC_ROOT/index.php" ] && \
   [ ! -f "$DOC_ROOT/index.html" ] && \
   [ ! -f "$DOC_ROOT/index.htm" ]; then
    
    echo "No index file found, copying default index.php..."
    
    # Ensure the default source directory exists
    if [ -f /opt/default-src/index.php ]; then
        cp /opt/default-src/index.php "$DOC_ROOT/index.php"
        chown www-data:www-data "$DOC_ROOT/index.php"
        chmod 644 "$DOC_ROOT/index.php"
        echo "✅ Default index.php copied to $DOC_ROOT/"
    else
        echo "⚠️  No default index.php found in /opt/default-src/"
    fi
else
    echo "✅ Index file already exists, skipping default copy"
fi