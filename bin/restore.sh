#!/bin/bash
# YaCy Restore Script
# Purpose: Restore YaCy from a backup file
# Usage: ./restore.sh <backup-file.tar.gz>
# Example: ./restore.sh ./backups/yacy_20260425_120000.tar.gz

set -e

# Check for required dependencies
for cmd in docker tar date jq curl; do
    if ! command -v "$cmd" &> /dev/null; then
        echo "Error: Required command '$cmd' not found."
        case "$cmd" in
            docker) echo "  Install Docker: https://docs.docker.com/engine/install/" ;;
            tar|date) echo "  Ubuntu/Debian: apt-get install tar coreutils" ;;
            jq|curl) echo "  Ubuntu/Debian: apt-get install jq curl" ;;
        esac
        exit 1
    fi
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
YACY_COMPOSE="$PROJECT_DIR/docker-compose.yml"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
LOG_PREFIX="[YaCy Restore $TIMESTAMP]"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Parse arguments
SKIP_CONFIRM=false
BACKUP_ARG=""

for arg in "$@"; do
    case "$arg" in
        -y|--yes) SKIP_CONFIRM=true ;;
        -*) echo -e "${RED}Unknown option: $arg${NC}"; exit 1 ;;
        *) BACKUP_ARG="$arg" ;;
    esac
done

if [ -z "$BACKUP_ARG" ]; then
    echo -e "${RED}Error: Backup file required${NC}"
    echo "Usage: $0 [-y] <backup-file.tar.gz>"
    echo "  -y, --yes    Skip confirmation prompt"
    echo "Example: $0 ./backups/yacy_20260425_120000.tar.gz"
    exit 1
fi

# Convert to absolute path (required for Docker bind mounts)
BACKUP_FILE="$(cd "$(dirname "$BACKUP_ARG")" && pwd)/$(basename "$BACKUP_ARG")"

# Validate backup file exists
if [ ! -f "$BACKUP_FILE" ]; then
    echo -e "${RED}$LOG_PREFIX Error: Backup file not found: $BACKUP_FILE${NC}"
    exit 1
fi

# Validate it's a tar.gz file
if ! tar -tzf "$BACKUP_FILE" >/dev/null 2>&1; then
    echo -e "${RED}$LOG_PREFIX Error: Invalid tar.gz file: $BACKUP_FILE${NC}"
    exit 1
fi

BACKUP_SIZE=$(du -h "$BACKUP_FILE" | cut -f1)
BACKUP_DATE=$(ls -l "$BACKUP_FILE" | awk '{print $6, $7, $8}')

echo -e "${YELLOW}$LOG_PREFIX Starting restore from backup${NC}"
echo "  Backup: $(basename "$BACKUP_FILE")"
echo "  Size: $BACKUP_SIZE"
echo "  Date: $BACKUP_DATE"
echo ""

# Get user confirmation (skip with -y flag)
if [ "$SKIP_CONFIRM" = false ]; then
    read -p "Continue with restore? This will REPLACE current YaCy data. (yes/no): " confirm
    if [ "$confirm" != "yes" ]; then
        echo "$LOG_PREFIX Restore cancelled"
        exit 0
    fi
fi

echo -e "${YELLOW}$LOG_PREFIX Stopping YaCy service...${NC}"
docker compose -f "$YACY_COMPOSE" down || {
    echo -e "${RED}$LOG_PREFIX Error: Failed to stop YaCy${NC}"
    exit 1
}

echo -e "${YELLOW}$LOG_PREFIX Waiting for containers to stop...${NC}"
sleep 5

# Get actual volume name (includes project prefix)
VOLUME_NAME=$(docker volume ls --filter name=yacy_data -q 2>/dev/null | head -1)
if [ -z "$VOLUME_NAME" ]; then
    VOLUME_NAME=$(docker compose -f "$YACY_COMPOSE" config --format json | jq -r '.volumes | keys[0]' 2>/dev/null || echo "yacy_yacy_data")
    [ -z "$VOLUME_NAME" ] || [ "$VOLUME_NAME" = "null" ] && VOLUME_NAME="yacy_yacy_data"
fi

if [ -z "$VOLUME_NAME" ] || [ "$VOLUME_NAME" = "null" ]; then
    VOLUME_NAME="yacy_yacy_data"
fi

echo -e "${YELLOW}$LOG_PREFIX Checking volume: $VOLUME_NAME${NC}"

# Check if volume exists
if ! docker volume inspect "$VOLUME_NAME" >/dev/null 2>&1; then
    echo -e "${YELLOW}$LOG_PREFIX Volume does not exist, creating...${NC}"
    docker volume create "$VOLUME_NAME" || {
        echo -e "${RED}$LOG_PREFIX Error: Failed to create volume${NC}"
        exit 1
    }
else
    echo -e "${YELLOW}$LOG_PREFIX Volume exists, clearing contents...${NC}"
    # Remove old data (mount volume and remove files)
    docker run --rm \
      -v "${VOLUME_NAME}:/data" \
      alpine:latest \
      sh -c "find /data -mindepth 1 -delete" 2>/dev/null || true
fi

echo -e "${YELLOW}$LOG_PREFIX Restoring backup into volume...${NC}"

# Extract backup into volume
docker run --rm \
  -v "${VOLUME_NAME}:/data" \
  -v "$(dirname "$BACKUP_FILE"):/backups:ro" \
  alpine:latest \
  tar -xzf "/backups/$(basename "$BACKUP_FILE")" -C /data \
  || {
    echo -e "${RED}$LOG_PREFIX Error: Failed to extract backup${NC}"
    exit 1
  }

echo -e "${GREEN}$LOG_PREFIX Backup extracted successfully${NC}"

# Verify restoration (check for key directories)
echo -e "${YELLOW}$LOG_PREFIX Verifying restoration...${NC}"
docker run --rm \
  -v "${VOLUME_NAME}:/data" \
  alpine:latest \
  sh -c "
    echo 'Directory contents:';
    ls -la /data | head -20;

    if [ -d /data/INDEX ]; then
      echo 'INDEX directory found ✓';
    else
      echo 'WARNING: INDEX directory not found';
    fi

    if [ -f /data/yacy.init ] || [ -d /data/defaults ]; then
      echo 'Configuration found ✓';
    else
      echo 'WARNING: Configuration not found';
    fi
  " || true

# Restart YaCy
echo -e "${YELLOW}$LOG_PREFIX Starting YaCy service...${NC}"
docker compose -f "$YACY_COMPOSE" up -d || {
    echo -e "${RED}$LOG_PREFIX Error: Failed to start YaCy${NC}"
    exit 1
}

# Wait for startup
echo -e "${YELLOW}$LOG_PREFIX Waiting for YaCy to start (60 seconds)...${NC}"
sleep 60

# Check health
echo -e "${YELLOW}$LOG_PREFIX Checking service health...${NC}"
if docker compose -f "$YACY_COMPOSE" ps | grep -q "yacy.*healthy"; then
    echo -e "${GREEN}$LOG_PREFIX YaCy is healthy ✓${NC}"
    echo ""
    echo -e "${GREEN}Restore completed successfully!${NC}"
    echo "YaCy is accessible at: https://yacy.example.com (update your domain)"
    echo ""
    exit 0
elif docker compose -f "$YACY_COMPOSE" ps | grep -q "yacy.*starting"; then
    echo -e "${YELLOW}$LOG_PREFIX YaCy is still starting, please check status in a few moments${NC}"
    docker compose -f "$YACY_COMPOSE" ps
    exit 0
else
    echo -e "${RED}$LOG_PREFIX Error: YaCy failed to start${NC}"
    docker compose -f "$YACY_COMPOSE" logs yacy | tail -50
    exit 1
fi
