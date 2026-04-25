#!/bin/bash
# YaCy Automated Backup Script
# Purpose: Back up YaCy search index and configuration
# Usage: ./backup.sh (run manually or via cron)
# Cron: 0 2 * * * /path/to/yacy/bin/backup.sh >> /var/log/yacy-backup.log 2>&1

set -e

# Check for required dependencies
for cmd in docker tar date find jq; do
    if ! command -v "$cmd" &> /dev/null; then
        echo "Error: Required command '$cmd' not found."
        case "$cmd" in
            docker) echo "  Install Docker: https://docs.docker.com/engine/install/" ;;
            tar|date|find) echo "  Ubuntu/Debian: apt-get install tar coreutils findutils" ;;
            jq) echo "  Ubuntu/Debian: apt-get install jq" ;;
        esac
        exit 1
    fi
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Load select variables from .env if present
if [ -f "$PROJECT_DIR/.env" ]; then
    BACKUP_DIR=$(grep -E "^BACKUP_DIR=" "$PROJECT_DIR/.env" 2>/dev/null | cut -d= -f2-)
    BACKUP_RETENTION_DAYS=$(grep -E "^BACKUP_RETENTION_DAYS=" "$PROJECT_DIR/.env" 2>/dev/null | cut -d= -f2-)
fi

# Resolve to absolute path (required for Docker bind mounts)
BACKUP_DIR="$(cd "$PROJECT_DIR" && mkdir -p "${BACKUP_DIR:-./backups}" && cd "${BACKUP_DIR:-./backups}" && pwd)"
BACKUP_RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-7}"
YACY_COMPOSE="$PROJECT_DIR/docker-compose.yml"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_PREFIX="[YaCy Backup $(date '+%Y-%m-%d %H:%M:%S')]"

# Ensure backup directory exists
mkdir -p "$BACKUP_DIR"

echo "$LOG_PREFIX Starting YaCy backup..."

# Verify compose file exists
if [ ! -f "$YACY_COMPOSE" ]; then
    echo "$LOG_PREFIX Error: docker-compose.yml not found at $YACY_COMPOSE"
    exit 1
fi

# Check if YaCy container is running
if ! docker compose -f "$YACY_COMPOSE" ps yacy | grep -q yacy; then
    echo "$LOG_PREFIX Warning: YaCy container not running. Attempting to backup volume anyway..."
fi

# Backup the named volume using a temporary container
echo "$LOG_PREFIX Backing up YaCy DATA volume..."

# Get actual volume name from running container (includes project prefix)
VOLUME_NAME=$(docker inspect yacy --format='{{range .Mounts}}{{if eq .Type "volume"}}{{.Name}}{{end}}{{end}}' 2>/dev/null | head -1)
if [ -z "$VOLUME_NAME" ]; then
    # Fallback: derive from compose config
    VOLUME_NAME=$(docker compose -f "$YACY_COMPOSE" config --format json | jq -r '.volumes | keys[0]' 2>/dev/null || echo "yacy_yacy_data")
    [ -z "$VOLUME_NAME" ] || [ "$VOLUME_NAME" = "null" ] && VOLUME_NAME="yacy_yacy_data"
fi

# Create backup using temporary container
docker run --rm \
  -v "${VOLUME_NAME}:/data:ro" \
  -v "$BACKUP_DIR:/backups" \
  alpine:latest \
  sh -c "tar -czf '/backups/yacy_${TIMESTAMP}.tar.gz' \
    -C /data . \
    --exclude='logs/*' \
    --exclude='*.tmp' \
    --exclude='*.tmp.*' \
    2>/dev/null" \
  || {
    echo "$LOG_PREFIX Error: Failed to create backup"
    exit 1
  }

# Verify backup was created
if [ ! -f "$BACKUP_DIR/yacy_${TIMESTAMP}.tar.gz" ]; then
    echo "$LOG_PREFIX Error: Backup file was not created"
    exit 1
fi

# Get backup size
BACKUP_SIZE=$(du -h "$BACKUP_DIR/yacy_${TIMESTAMP}.tar.gz" | cut -f1)
echo "$LOG_PREFIX Backup created successfully: yacy_${TIMESTAMP}.tar.gz ($BACKUP_SIZE)"

# Cleanup old backups (older than retention period)
echo "$LOG_PREFIX Cleaning up backups older than $BACKUP_RETENTION_DAYS days..."
OLD_BACKUPS=$(find "$BACKUP_DIR" -name "yacy_*.tar.gz" -mtime +"$BACKUP_RETENTION_DAYS" 2>/dev/null | wc -l)

if [ "$OLD_BACKUPS" -gt 0 ]; then
    find "$BACKUP_DIR" -name "yacy_*.tar.gz" -mtime +"$BACKUP_RETENTION_DAYS" -delete
    echo "$LOG_PREFIX Removed $OLD_BACKUPS old backup(s)"
else
    echo "$LOG_PREFIX No old backups to remove"
fi

# Verify we have at least 2 recent backups
BACKUP_COUNT=$(ls -1 "$BACKUP_DIR"/yacy_*.tar.gz 2>/dev/null | wc -l)
if [ "$BACKUP_COUNT" -lt 2 ]; then
    echo "$LOG_PREFIX Warning: Only $BACKUP_COUNT backup(s) exist. Monitor backup success."
fi

# Calculate total backup storage
TOTAL_SIZE=$(du -sh "$BACKUP_DIR" 2>/dev/null | cut -f1)
echo "$LOG_PREFIX Backup directory total size: $TOTAL_SIZE ($BACKUP_COUNT backups)"

# Test backup integrity (optional - uncomment to enable)
# echo "$LOG_PREFIX Testing backup integrity..."
# if tar -tzf "$BACKUP_DIR/yacy_${TIMESTAMP}.tar.gz" >/dev/null 2>&1; then
#     echo "$LOG_PREFIX Backup integrity verified ✓"
# else
#     echo "$LOG_PREFIX Error: Backup integrity check failed"
#     exit 1
# fi

echo "$LOG_PREFIX Backup completed successfully"
exit 0
