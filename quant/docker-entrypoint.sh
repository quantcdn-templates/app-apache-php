#!/bin/bash
# Custom entrypoint for Apache+PHP that runs initialization scripts
# This is needed for local development; in Quant Cloud, the platform wrapper handles this

set -e

# Run custom entrypoint scripts if they exist
if [ -d "/quant-entrypoint.d" ]; then
    for script in /quant-entrypoint.d/*.sh; do
        if [ -f "$script" ] && [ -x "$script" ]; then
            echo "Running $(basename "$script")..."
            "$script"
        fi
    done
fi

# Pass control to the original docker-php-entrypoint
exec docker-php-entrypoint "$@"

