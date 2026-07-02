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
# QUANT_WF_LOCAL_WFLOGS:
#   auto (default) - relocate only when wflogs lives on network storage (NFS);
#                    no-op on local disk, where relocation buys nothing
#   1              - always relocate
#   0              - never relocate; revert an earlier relocation

QUANT_WF_LOCAL_WFLOGS="${QUANT_WF_LOCAL_WFLOGS:-auto}"
WP_ROOT="${DOCUMENT_ROOT:-/var/www/html}"
WFLOGS="${WP_ROOT}/wp-content/wflogs"
BACKUP="${WP_ROOT}/wp-content/wflogs.pre-local"
LOCAL=/var/lib/quant/wflogs

wants_relocation() {
    case "$QUANT_WF_LOCAL_WFLOGS" in
        1) return 0 ;;
        auto)
            # Relocate in auto mode only when wflogs sits on NFS (e.g. EFS).
            # A pre-existing symlink means a previous boot already decided.
            [ -L "$WFLOGS" ] && return 0
            fstype=$(stat -f -c %T "$WFLOGS" 2>/dev/null)
            case "$fstype" in nfs*) return 0 ;; esac
            return 1 ;;
        *) return 1 ;;
    esac
}

if [ -d "$WFLOGS" ] || [ -L "$WFLOGS" ]; then
    if wants_relocation; then
        if [ ! -L "$WFLOGS" ]; then
            mkdir -p "$LOCAL"
            cp -a "$WFLOGS/." "$LOCAL/" 2>/dev/null || true
            rm -rf "$BACKUP"
            mv "$WFLOGS" "$BACKUP"
            ln -s "$LOCAL" "$WFLOGS"
            echo "✅ wflogs relocated to local disk (${LOCAL}); previous copy at ${BACKUP}"
        elif [ ! -d "$LOCAL" ]; then
            # Another container already converted the shared volume: make sure
            # the local target exists on THIS node, seeded from the backup.
            mkdir -p "$LOCAL"
            [ -d "$BACKUP" ] && cp -a "$BACKUP/." "$LOCAL/" 2>/dev/null || true
            echo "✅ wflogs local target created for this container (${LOCAL})"
        fi
        chown -R www-data:www-data "$LOCAL" 2>/dev/null || true
    elif [ "$QUANT_WF_LOCAL_WFLOGS" = "0" ] && [ -L "$WFLOGS" ]; then
        # Explicitly disabled: revert so Wordfence writes to the volume again.
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
