#!/bin/bash
# Solr Initialization Script for YaCy
# Purpose: Create Solr cores with YaCy's schema for federated search
# Usage: ./solr-init.sh
# Ref: https://yacy.net/dev/solr/
#
# This script:
# 1. Extracts YaCy's Solr schema from the running YaCy container
# 2. Creates cores in Solr with that schema
# 3. Shows how to enable external Solr in YaCy

set -e

for cmd in docker curl; do
    if ! command -v "$cmd" &> /dev/null; then
        echo "Error: Required command '$cmd' not found."
        exit 1
    fi
done

YACY_CONTAINER=${YACY_CONTAINER:-yacy}
SOLR_CONTAINER=${SOLR_CONTAINER:-yacy-solr}
SOLR_PORT=${SOLR_PORT:-8983}
SOLR_HOST=${SOLR_HOST:-127.0.0.1}
SOLR_URL="http://${SOLR_HOST}:${SOLR_PORT}"
CORES=("collection1" "webgraph")

echo "=========================================="
echo "YaCy Solr Integration Setup"
echo "=========================================="
echo ""
echo "YaCy container: $YACY_CONTAINER"
echo "Solr container: $SOLR_CONTAINER"
echo "Solr URL:       $SOLR_URL"
echo "Cores:          ${CORES[*]}"
echo ""

# Check containers are running
for c in "$YACY_CONTAINER" "$SOLR_CONTAINER"; do
    if ! docker ps --format '{{.Names}}' | grep -q "^${c}$"; then
        echo "✗ Error: Container '$c' is not running"
        echo "  Start with: docker compose up -d"
        exit 1
    fi
done

# Wait for Solr (via docker exec, works regardless of port mapping)
echo "Waiting for Solr..."
ATTEMPT=0
while [ $ATTEMPT -lt 30 ]; do
    if docker exec "$SOLR_CONTAINER" curl -sf http://localhost:8983/api/node/health > /dev/null 2>&1; then
        echo "✓ Solr is ready"
        break
    fi
    ATTEMPT=$((ATTEMPT + 1))
    sleep 2
done
[ $ATTEMPT -eq 30 ] && echo "✗ Solr not ready" && exit 1

# Wait for YaCy (via docker exec, works regardless of port mapping)
echo "Waiting for YaCy..."
ATTEMPT=0
while [ $ATTEMPT -lt 30 ]; do
    if docker exec "$YACY_CONTAINER" curl -sf http://localhost:8090/ > /dev/null 2>&1; then
        echo "✓ YaCy is ready"
        break
    fi
    ATTEMPT=$((ATTEMPT + 1))
    sleep 2
done
[ $ATTEMPT -eq 30 ] && echo "✗ YaCy not ready" && exit 1

echo ""

# Step 1: Extract YaCy's Solr schema and config
echo "Extracting YaCy Solr config..."

# Copy YaCy's bundled Solr configs to the Solr container
for CORE in "${CORES[@]}"; do
    echo "  Setting up core: $CORE"

    # Check if core already exists
    if docker exec "$SOLR_CONTAINER" curl -s http://localhost:8983/solr/admin/cores?action=STATUS\&core=$CORE 2>/dev/null | grep -q '"instanceDir"'; then
        echo "    → Core already exists, skipping"
        continue
    fi

    # Create core with _default configset, then overlay YaCy's schema
    CREATE_OUTPUT=$(docker exec "$SOLR_CONTAINER" solr create_core -c "$CORE" 2>&1)
    if echo "$CREATE_OUTPUT" | grep -qi "created\|already exists"; then
        echo "    ✓ Core created: $CORE"
    else
        echo "    ✗ Failed to create core: $CORE"
        echo "    $CREATE_OUTPUT" | grep -i "error" | head -2
        exit 1
    fi

    # Replace schema with YaCy's bundled version (shared schema for all cores)
    # See: https://yacy.net/dev/solr/
    YACY_SCHEMA="/opt/yacy_search_server/defaults/solr/schema.xml"
    if docker exec "$YACY_CONTAINER" test -f "$YACY_SCHEMA" 2>/dev/null; then
        docker cp "$YACY_CONTAINER:$YACY_SCHEMA" "/tmp/yacy_schema.xml"
        docker cp "/tmp/yacy_schema.xml" "$SOLR_CONTAINER:/var/solr/data/${CORE}/conf/managed-schema.xml"

        # Also copy solrconfig.xml if available
        YACY_SOLRCONFIG="/opt/yacy_search_server/defaults/solr/solrconfig.xml"
        if docker exec "$YACY_CONTAINER" test -f "$YACY_SOLRCONFIG" 2>/dev/null; then
            docker cp "$YACY_CONTAINER:$YACY_SOLRCONFIG" "/tmp/yacy_solrconfig.xml"
            docker cp "/tmp/yacy_solrconfig.xml" "$SOLR_CONTAINER:/var/solr/data/${CORE}/conf/solrconfig.xml"
            rm -f "/tmp/yacy_solrconfig.xml"
        fi

        rm -f "/tmp/yacy_schema.xml"
        echo "    ✓ YaCy schema applied to: $CORE"
    else
        echo "    ⚠ YaCy schema not found, using Solr defaults"
    fi

    sleep 1
done

# Reload cores to pick up schema changes
echo ""
echo "Reloading cores..."
for CORE in "${CORES[@]}"; do
    RESULT=$(docker exec "$SOLR_CONTAINER" curl -s "http://localhost:8983/solr/admin/cores?action=RELOAD&core=$CORE" 2>/dev/null)
    if echo "$RESULT" | grep -q '"status":0'; then
        echo "  ✓ Reloaded: $CORE"
    else
        echo "  ⚠ Reload warning for $CORE (may need restart)"
    fi
done

echo ""
echo "=========================================="
echo "Setup Complete"
echo "=========================================="
echo ""
echo "Verify cores:"
echo "  Solr Admin: $SOLR_URL/solr/#/"
echo "  curl '$SOLR_URL/solr/admin/cores?action=STATUS'"
echo ""

# Step 2: Configure YaCy to use external Solr
echo "Configuring YaCy to use external Solr..."
SOLR_INTERNAL_URL="${SOLR_INTERNAL_URL:-http://solr:8983/solr/}"
YACY_CONF="/opt/yacy_search_server/DATA/SETTINGS/yacy.conf"

if docker exec "$YACY_CONTAINER" test -f "$YACY_CONF" 2>/dev/null; then
    docker exec "$YACY_CONTAINER" sed -i \
        -e "s|federated.service.solr.indexing.enabled=.*|federated.service.solr.indexing.enabled=true|" \
        -e "s|federated.service.solr.indexing.url=.*|federated.service.solr.indexing.url=${SOLR_INTERNAL_URL}|" \
        "$YACY_CONF"
    echo "  ✓ External Solr enabled in yacy.conf"
    echo "  ✓ Solr URL: $SOLR_INTERNAL_URL"
    echo ""
    echo "Restart YaCy to apply:"
    echo "  docker compose restart yacy"
else
    echo "  ⚠ yacy.conf not found, configure manually:"
    echo "    Go to http://localhost:8090/IndexFederated_p.html"
    echo "    Uncheck 'Use deep-embedded local Solr'"
    echo "    Check 'Use remote Solr server(s)'"
    echo "    Set Solr URL: $SOLR_INTERNAL_URL"
fi

echo ""
echo "Ref: https://yacy.net/dev/solr/"
