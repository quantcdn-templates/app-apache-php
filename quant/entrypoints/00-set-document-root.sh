#!/bin/bash
# Entrypoint script to configure Apache DocumentRoot based on DOCUMENT_ROOT env var
# Runs at container startup before Apache starts

set -euo pipefail

NEW_DOC_ROOT="${DOCUMENT_ROOT:-/var/www/html}"

# Skip if already at default (optimization for most common case)
if [ "$NEW_DOC_ROOT" = "/var/www/html" ]; then
    exit 0
fi

PARENT_DIR=$(dirname "$NEW_DOC_ROOT")

echo "[set-document-root] Configuring Apache DocumentRoot: $NEW_DOC_ROOT"

# Update DocumentRoot in Apache config
sed -i "s|DocumentRoot /var/www/html|DocumentRoot ${NEW_DOC_ROOT}|g" /etc/apache2/sites-available/000-default.conf

# Update Directory directive in apache2.conf
sed -i "s|<Directory /var/www/>|<Directory ${PARENT_DIR}/>|g" /etc/apache2/apache2.conf

# Create directory if it doesn't exist
mkdir -p "$NEW_DOC_ROOT"

echo "[set-document-root] ✅ DocumentRoot configured: $NEW_DOC_ROOT"
