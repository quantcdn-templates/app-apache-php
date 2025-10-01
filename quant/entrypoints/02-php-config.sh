#!/bin/bash

# Configure PHP settings from environment variables
# This script processes PHP ini template files and substitutes environment variables

echo "Configuring PHP settings from environment variables..."

# Set default values if not provided
export PHP_MEMORY_LIMIT="${PHP_MEMORY_LIMIT:-256M}"
export PHP_UPLOAD_MAX_FILESIZE="${PHP_UPLOAD_MAX_FILESIZE:-128M}"
export PHP_POST_MAX_SIZE="${PHP_POST_MAX_SIZE:-150M}"
export PHP_MAX_FILE_UPLOADS="${PHP_MAX_FILE_UPLOADS:-50}"
export PHP_MAX_INPUT_VARS="${PHP_MAX_INPUT_VARS:-3000}"
export PHP_MAX_EXECUTION_TIME="${PHP_MAX_EXECUTION_TIME:-300}"
export PHP_MAX_INPUT_TIME="${PHP_MAX_INPUT_TIME:-300}"

# Process template files with envsubst
for template in /usr/local/etc/php/conf.d/*.template; do
    if [ -f "$template" ]; then
        # Get the target filename by removing .template extension
        target="${template%.template}"
        echo "Processing $template -> $target"
        
        # Use envsubst to substitute environment variables
        envsubst < "$template" > "$target"
        
        # Log the configuration values for debugging
        echo "✅ PHP configuration applied:"
        cat "$target"
        echo ""
    fi
done

echo "✅ PHP configuration completed"