#!/bin/bash

# Relocate Wordfence's wflogs directory from the (network) persistent volume
# to container-local disk. The Wordfence WAF re-reads several MB of PHP data
# files from wflogs on every request and rewrites its state files continuously;
# on network storage where I/O is billed (EFS) that is the dominant traffic on
# otherwise-idle sites. WAF state is per-node by design on load-balanced
# setups: on a fresh container Wordfence re-syncs rules from its API, so local
# storage only costs that node's attack-log history (still visible in the
# Wordfence dashboard).
#
# Opt-in via QUANT_WF_LOCAL_WFLOGS=1. With the flag off (default) an earlier
# relocation is reverted so sites can roll back by unsetting the env var.

QUANT_WF_LOCAL_WFLOGS="${QUANT_WF_LOCAL_WFLOGS:-0}"
WP_ROOT="${DOCUMENT_ROOT:-/var/www/html}"
WFLOGS="${WP_ROOT}/wp-content/wflogs"
BACKUP="${WP_ROOT}/wp-content/wflogs.pre-local"
LOCAL=/var/lib/quant/wflogs

if [ "$QUANT_WF_LOCAL_WFLOGS" = "1" ]; then
    # Nothing to do unless Wordfence has created wflogs
    if [ -d "$WFLOGS" ] && [ ! -L "$WFLOGS" ]; then
        mkdir -p "$LOCAL"
        cp -a "$WFLOGS/." "$LOCAL/" 2>/dev/null || true
        rm -rf "$BACKUP"
        mv "$WFLOGS" "$BACKUP"
        ln -s "$LOCAL" "$WFLOGS"
        echo "✅ wflogs relocated to local disk (${LOCAL}); previous copy at ${BACKUP}"
    elif [ -L "$WFLOGS" ]; then
        # Another container already converted the shared volume: make sure the
        # local target exists on THIS node, seeded from the backup if present.
        if [ ! -d "$LOCAL" ]; then
            mkdir -p "$LOCAL"
            [ -d "$BACKUP" ] && cp -a "$BACKUP/." "$LOCAL/" 2>/dev/null || true
            echo "✅ wflogs local target created for this container (${LOCAL})"
        fi
    fi
    chown -R www-data:www-data "$LOCAL" 2>/dev/null || true
else
    # Flag off: revert a previous relocation so Wordfence writes to the
    # persistent volume again.
    if [ -L "$WFLOGS" ]; then
        rm -f "$WFLOGS"
        if [ -d "$BACKUP" ]; then
            mv "$BACKUP" "$WFLOGS"
        else
            mkdir -p "$WFLOGS"
            chown www-data:www-data "$WFLOGS" 2>/dev/null || true
        fi
        echo "✅ wflogs relocation reverted (back on persistent volume)"
    fi
fi
