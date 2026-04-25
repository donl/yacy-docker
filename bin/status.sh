#!/bin/bash
# YaCy Status & Version Script
# Purpose: Show running version, resource usage, disk space, and health status
# Usage: ./status.sh

set -e

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Check for required dependencies
for cmd in docker jq; do
    if ! command -v "$cmd" &> /dev/null; then
        echo "Error: Required command '$cmd' not found."
        case "$cmd" in
            docker) echo "  Install Docker: https://docs.docker.com/engine/install/" ;;
            jq) echo "  Ubuntu/Debian: apt-get install jq" ;;
        esac
        exit 1
    fi
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTAINER_NAME="yacy"
YACY_COMPOSE="$SCRIPT_DIR/../docker-compose.yml"

# Helper functions
print_header() {
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}$1${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

status_ok() {
    echo -e "  ${GREEN}✓${NC} $1"
}

status_warn() {
    echo -e "  ${YELLOW}⚠${NC} $1"
}

status_error() {
    echo -e "  ${RED}✗${NC} $1"
}

print_stat() {
    printf "  ${YELLOW}%-30s${NC} %s\n" "$1:" "$2"
}

# Check if container exists and is running
print_header "CONTAINER STATUS"

if ! docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    status_error "Container '$CONTAINER_NAME' not found"
    exit 1
fi

if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    status_ok "Container is running"
    RUNNING=true
else
    status_warn "Container is not running"
    RUNNING=false
fi

echo ""

# Get container details
print_header "VERSION & BUILD INFORMATION"

if [ "$RUNNING" = true ]; then
    # Get image ID and creation date
    IMAGE_ID=$(docker inspect "$CONTAINER_NAME" --format='{{.Image}}' | cut -d@ -f2 | cut -c1-12)
    IMAGE_NAME=$(docker inspect "$CONTAINER_NAME" --format='{{.Config.Image}}')

    print_stat "Image Name" "$IMAGE_NAME"
    print_stat "Image ID" "$IMAGE_ID"

    # Get image labels (version, SHA, build date)
    YACY_VERSION=$(docker inspect "$IMAGE_NAME" 2>/dev/null | jq -r '.[0].Config.Labels["org.opencontainers.image.version"] // "unknown"' 2>/dev/null || echo "unknown")
    BUILD_DATE=$(docker inspect "$IMAGE_NAME" 2>/dev/null | jq -r '.[0].Config.Labels["org.opencontainers.image.created"] // "unknown"' 2>/dev/null || echo "unknown")

    print_stat "YaCy Version" "$YACY_VERSION"
    print_stat "Build Date" "$BUILD_DATE"

    # Get started time and uptime
    STARTED=$(docker inspect "$CONTAINER_NAME" --format='{{.State.StartedAt}}')
    STARTED_READABLE=$(date -d "$STARTED" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "$STARTED")

    print_stat "Started At" "$STARTED_READABLE"

    # Calculate uptime
    STARTED_EPOCH=$(date -d "$STARTED" +%s 2>/dev/null || echo 0)
    NOW_EPOCH=$(date +%s)
    UPTIME_SECONDS=$((NOW_EPOCH - STARTED_EPOCH))
    UPTIME_DAYS=$((UPTIME_SECONDS / 86400))
    UPTIME_HOURS=$(((UPTIME_SECONDS % 86400) / 3600))
    UPTIME_MINS=$(((UPTIME_SECONDS % 3600) / 60))

    print_stat "Uptime" "${UPTIME_DAYS}d ${UPTIME_HOURS}h ${UPTIME_MINS}m"
else
    status_warn "Cannot get version info - container not running"
fi

echo ""

# Resource usage
print_header "RESOURCE USAGE"

if [ "$RUNNING" = true ]; then
    # Get stats (timeout after 5 seconds to avoid hanging)
    STATS=$(timeout 5 docker stats "$CONTAINER_NAME" --no-stream --format='{{.CPUPerc}}|{{.MemUsage}}|{{.MemPerc}}' 2>/dev/null || echo "N/A|N/A|N/A")

    CPU_USAGE=$(echo "$STATS" | cut -d'|' -f1)
    MEM_USAGE=$(echo "$STATS" | cut -d'|' -f2)
    MEM_PERCENT=$(echo "$STATS" | cut -d'|' -f3)

    if [ "$CPU_USAGE" != "N/A" ]; then
        print_stat "CPU Usage" "$CPU_USAGE"
        print_stat "Memory Usage" "$MEM_USAGE"
        print_stat "Memory %" "$MEM_PERCENT"
    else
        status_warn "Could not retrieve real-time stats"
    fi
else
    status_warn "Container not running - no resource stats available"
fi

echo ""

# Disk usage (via Docker volume)
print_header "DISK USAGE"

if [ "$RUNNING" = true ]; then
    # Get actual volume name from running container's mounts
    VOLUME_NAME=$(docker inspect "$CONTAINER_NAME" --format='{{range .Mounts}}{{if eq .Type "volume"}}{{.Name}}{{end}}{{end}}' 2>/dev/null | head -1)
    [ -z "$VOLUME_NAME" ] && VOLUME_NAME="yacy_yacy_data"

    # Get volume size by running du inside a temporary container
    VOLUME_SIZE=$(docker run --rm -v "${VOLUME_NAME}:/data" alpine du -sh /data 2>/dev/null | awk '{print $1}')
    if [ -n "$VOLUME_SIZE" ]; then
        print_stat "Data Volume" "$VOLUME_NAME ($VOLUME_SIZE)"

        # Get subdirectory sizes
        VOLUME_BREAKDOWN=$(docker run --rm -v "${VOLUME_NAME}:/data" alpine sh -c "du -sh /data/INDEX 2>/dev/null; du -sh /data/SETTINGS 2>/dev/null" 2>/dev/null || echo "")
        if [ -n "$VOLUME_BREAKDOWN" ]; then
            INDEX_SIZE=$(echo "$VOLUME_BREAKDOWN" | grep INDEX | awk '{print $1}')
            CONFIG_SIZE=$(echo "$VOLUME_BREAKDOWN" | grep SETTINGS | awk '{print $1}')
            [ -n "$INDEX_SIZE" ] && print_stat "  ├─ Index Size" "$INDEX_SIZE"
            [ -n "$CONFIG_SIZE" ] && print_stat "  └─ Config Size" "$CONFIG_SIZE"
        fi
    else
        status_warn "Could not determine volume size"
    fi

    # Image size
    IMAGE_SIZE=$(docker image inspect "$IMAGE_NAME" 2>/dev/null | jq -r '.[0].Size' 2>/dev/null || echo "")
    if [ -n "$IMAGE_SIZE" ] && [ "$IMAGE_SIZE" != "null" ]; then
        IMAGE_SIZE_HR=$(numfmt --to=iec "$IMAGE_SIZE" 2>/dev/null || echo "$IMAGE_SIZE bytes")
        print_stat "Image Size" "$IMAGE_SIZE_HR"
    fi
else
    status_warn "Container not running - disk usage unavailable"
fi

echo ""

# Health check
print_header "HEALTH STATUS"

if [ "$RUNNING" = true ]; then
    HEALTH=$(docker inspect "$CONTAINER_NAME" --format='{{.State.Health.Status}}' 2>/dev/null || echo "unknown")

    case "$HEALTH" in
        "healthy")
            status_ok "Container health: $HEALTH"
            ;;
        "unhealthy")
            status_error "Container health: $HEALTH"
            echo -e "  ${YELLOW}Logs:${NC}"
            docker inspect "$CONTAINER_NAME" --format='{{.State.Health.Log | json}}' 2>/dev/null | jq -r '.[-1].Output' 2>/dev/null | sed 's/^/    /' || echo "    (health log unavailable)"
            ;;
        *)
            status_warn "Container health: $HEALTH"
            ;;
    esac

    # Try to ping YaCy
    if timeout 5 docker exec "$CONTAINER_NAME" curl -sf http://localhost:8090/ > /dev/null 2>&1; then
        status_ok "YaCy web interface responding"

        # Get peer info from hello endpoint
        HELLO=$(timeout 5 docker exec "$CONTAINER_NAME" curl -sf http://localhost:8090/yacy/hello.html 2>/dev/null || echo "")
        if [ -n "$HELLO" ]; then
            PEER_NAME=$(echo "$HELLO" | grep "^peerName=" | cut -d= -f2)
            UPTIME=$(echo "$HELLO" | grep "^uptime=" | cut -d= -f2)
            [ -n "$PEER_NAME" ] && print_stat "Peer Name" "$PEER_NAME"
            [ -n "$UPTIME" ] && print_stat "YaCy Uptime (min)" "$UPTIME"
        fi
    else
        status_warn "YaCy not responding"
    fi
else
    status_error "Container not running - health check unavailable"
fi

echo ""

# Optional: Solr status
if [ "$RUNNING" = true ]; then
    if docker compose -f "$YACY_COMPOSE" ps 2>/dev/null | grep -q "solr"; then
        print_header "SOLR STATUS"

        if docker ps --format '{{.Names}}' | grep -q "solr"; then
            status_ok "Solr container is running"

            # Check Solr cores (standalone mode)
            CORES=$(timeout 5 docker exec yacy-solr curl -s http://localhost:8983/solr/admin/cores?action=STATUS 2>/dev/null | jq -r '.status | keys[]' 2>/dev/null || echo "")

            if [ -n "$CORES" ]; then
                print_stat "Cores" "$(echo "$CORES" | tr '\n' ', ' | sed 's/,$//')"
            else
                status_warn "No Solr cores found"
            fi
        else
            status_warn "Solr container not running"
        fi

        echo ""
    fi
fi

# Summary
print_header "QUICK COMMANDS"

echo -e "  ${CYAN}View logs:${NC}       docker compose logs -f yacy"
echo -e "  ${CYAN}Restart:${NC}         docker compose restart yacy"
echo -e "  ${CYAN}Stop:${NC}            docker compose stop yacy"
echo -e "  ${CYAN}Admin panel:${NC}     http://localhost:8090"
echo -e "  ${CYAN}Peer info:${NC}       curl http://localhost:8090/yacy/hello.html"
echo ""
