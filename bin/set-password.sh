#!/bin/bash
# Set YaCy admin password
# Usage: ./set-password.sh [container-name] [password]
# Default container name: yacy

set -e

# Check for required dependencies
for cmd in docker md5sum sed; do
    if ! command -v "$cmd" &> /dev/null; then
        echo "Error: Required command '$cmd' not found."
        case "$cmd" in
            docker)
                echo "  Install Docker: https://docs.docker.com/engine/install/"
                ;;
            md5sum|sed)
                echo "  Ubuntu/Debian: apt-get install coreutils"
                ;;
        esac
        exit 1
    fi
done

CONTAINER="${1:-yacy}"
PASSWORD="${2}"

if [ -z "$PASSWORD" ]; then
    echo "Usage: $0 [container-name] [password]"
    echo ""
    echo "Examples:"
    echo "  $0 yacy mynewpassword"
    echo "  $0 yacy_prod securepassword123"
    exit 1
fi

# Check if container exists
if ! docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER}$"; then
    echo "Error: Container '$CONTAINER' not found"
    exit 1
fi

# Check if container is running
if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER}$"; then
    echo "Error: Container '$CONTAINER' is not running"
    echo "Start it with: docker compose up -d"
    exit 1
fi

echo "Setting YaCy admin password..."

# Generate MD5 hash of the password
# YaCy uses MD5: prefix format
# Note: This is a simplified hash. YaCy may use additional encoding/salting.
# If this doesn't work, you'll need to manually set it via the web UI.
PASSWORD_HASH=$(echo -n "$PASSWORD" | md5sum | awk '{print $1}')

echo "Generated MD5: $PASSWORD_HASH"
echo ""

# Update password in active config (DATA/SETTINGS/yacy.conf) and defaults
YACY_CONF="/opt/yacy_search_server/DATA/SETTINGS/yacy.conf"
YACY_INIT="/opt/yacy_search_server/defaults/yacy.init"

# Update active config if it exists (running instance)
if docker exec "$CONTAINER" test -f "$YACY_CONF" 2>/dev/null; then
    docker exec "$CONTAINER" sed -i \
        "/adminAccountBase64MD5=/c\\adminAccountBase64MD5=MD5:${PASSWORD_HASH}" \
        "$YACY_CONF"
    echo "Password updated in yacy.conf (active config)"
fi

# Also update defaults (applies on fresh DATA volume)
docker exec "$CONTAINER" sed -i \
    "/adminAccountBase64MD5=/c\\adminAccountBase64MD5=MD5:${PASSWORD_HASH}" \
    "$YACY_INIT"

echo ""
echo "Restart to apply:"
echo "  docker restart $CONTAINER"
echo ""
echo "If password doesn't work, set manually via web UI:"
echo "  http://localhost:8090 → Settings > Access > Admin Password"
