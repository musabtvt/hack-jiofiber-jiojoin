#!/bin/sh
# ==============================================================================
# Jio Voice OpenWrt - Safety Backup & Instant Rollback Utility
# ==============================================================================

BACKUP_DIR="/etc/jio-voice/backups"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

usage() {
    echo "Usage: $0 [--backup | --restore [FILE] | --list]"
    echo "  --backup         Create a snapshot of current network & firewall configuration"
    echo "  --restore [FILE] Restore settings from latest backup or specified tar.gz"
    echo "  --list           List all available backup archives"
    exit 1
}

case "$1" in
    --backup)
        mkdir -p "$BACKUP_DIR"
        BACKUP_FILE="$BACKUP_DIR/backup_${TIMESTAMP}.tar.gz"
        echo "[*] Creating backup at $BACKUP_FILE..."
        tar -czf "$BACKUP_FILE" /etc/config/network /etc/config/firewall /etc/config/dhcp 2>/dev/null
        echo "[SUCCESS] Configuration backed up successfully to $BACKUP_FILE"
        ;;

    --restore)
        if [ -n "$2" ] && [ -f "$2" ]; then
            TARGET="$2"
        else
            # Find latest backup
            TARGET=$(ls -t "$BACKUP_DIR"/backup_*.tar.gz 2>/dev/null | head -n 1)
        fi

        if [ -z "$TARGET" ] || [ ! -f "$TARGET" ]; then
            echo "[-] Error: No backup archive found to restore in $BACKUP_DIR."
            exit 1
        fi

        echo "[*] Restoring configurations from $TARGET..."
        tar -xzf "$TARGET" -C /
        echo "[*] Reloading network and firewall services..."
        /etc/init.d/network reload
        /etc/init.d/firewall reload
        echo "[SUCCESS] Router configuration reverted to snapshot state."
        ;;

    --list)
        echo "Available backups in $BACKUP_DIR:"
        ls -lh "$BACKUP_DIR"/backup_*.tar.gz 2>/dev/null || echo "No backups found."
        ;;

    *)
        usage
        ;;
esac
