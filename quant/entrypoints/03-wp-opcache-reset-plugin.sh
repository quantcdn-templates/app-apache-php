#!/bin/bash

# Install the Quant OPcache reset mu-plugin into a WordPress install whose
# code lives on the persistent volume (e.g. Quant Cloud sites running this
# base image with WordPress on EFS). The mu-plugin calls opcache_reset() on
# plugin/theme changes, which is what makes PHP_OPCACHE_VALIDATE_TIMESTAMPS=0
# safe: without it, admin-driven code changes would never take effect.
# Disable with QUANT_WP_OPCACHE_RESET=0.

QUANT_WP_OPCACHE_RESET="${QUANT_WP_OPCACHE_RESET:-1}"
WP_ROOT="${DOCUMENT_ROOT:-/var/www/html}"
MU_SRC="/opt/quant/wp-mu-plugins/quant-opcache.php"
MU_DIR="${WP_ROOT}/wp-content/mu-plugins"

if [ "$QUANT_WP_OPCACHE_RESET" != "1" ]; then
    exit 0
fi

# Only act on an actual WordPress install
if [ ! -f "${WP_ROOT}/wp-load.php" ] || [ ! -d "${WP_ROOT}/wp-content" ]; then
    exit 0
fi

if [ -f "$MU_SRC" ]; then
    mkdir -p "$MU_DIR"
    if ! cmp -s "$MU_SRC" "${MU_DIR}/quant-opcache.php"; then
        cp "$MU_SRC" "${MU_DIR}/quant-opcache.php"
        chown www-data:www-data "${MU_DIR}/quant-opcache.php" 2>/dev/null || true
        echo "✅ Installed quant-opcache mu-plugin into ${MU_DIR}"
    fi
fi
