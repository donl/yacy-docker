#!/bin/bash
# YaCy Docker Stack - Test Suite
# Usage: ./bin/test.sh [unit|build|integration|all]
# Default: unit (fast, no Docker required for most checks)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

PASS=0
FAIL=0
SKIP=0

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

pass() { echo -e "  ${GREEN}✓${NC} $1"; PASS=$((PASS + 1)); }
fail() { echo -e "  ${RED}✗${NC} $1"; FAIL=$((FAIL + 1)); }
skip() { echo -e "  ${YELLOW}⊘${NC} $1 (skipped)"; SKIP=$((SKIP + 1)); }

header() { echo ""; echo -e "${YELLOW}=== $1 ===${NC}"; }

# ============================================================
# Unit Tests (no Docker needed)
# ============================================================
test_unit() {
    header "Script Syntax"
    for f in bin/*.sh; do
        if bash -n "$f" 2>/dev/null; then
            pass "$(basename $f) syntax OK"
        else
            fail "$(basename $f) syntax error"
        fi
    done

    header "Compose Validation"
    for f in docker-compose.*.yml; do
        [ ! -f "$f" ] && continue
        if [[ "$f" == *"solr"* ]]; then
            # Solr is an overlay, validate with a base
            if docker compose -f docker-compose.standalone.yml -f "$f" config > /dev/null 2>&1; then
                pass "$f validates (with standalone base)"
            else
                fail "$f invalid"
            fi
        else
            if docker compose -f "$f" config > /dev/null 2>&1; then
                pass "$f validates"
            else
                fail "$f invalid"
            fi
        fi
    done

    header "Required Files"
    for f in .env_example .gitignore .dockerignore LICENSE README.md Makefile; do
        [ -f "$f" ] && pass "$f exists" || fail "$f missing"
    done

    for f in bin/build.sh bin/status.sh bin/backup.sh bin/restore.sh bin/set-password.sh bin/solr-init.sh; do
        if [ -f "$f" ] && [ -x "$f" ]; then
            pass "$f exists and executable"
        elif [ -f "$f" ]; then
            fail "$f exists but not executable"
        else
            fail "$f missing"
        fi
    done

    header "Dockerfiles"
    for f in docker/Dockerfile docker/Dockerfile.alpine docker/Dockerfile.aarch64 docker/Dockerfile.armv7; do
        if [ -f "$f" ]; then
            pass "$(basename $f) exists"
            # Check for required directives
            grep -q "HEALTHCHECK" "$f" && pass "  $(basename $f) has HEALTHCHECK" || fail "  $(basename $f) missing HEALTHCHECK"
            grep -q "USER yacy" "$f" && pass "  $(basename $f) runs as non-root" || fail "  $(basename $f) missing USER directive"
            grep -q "LABEL" "$f" && pass "  $(basename $f) has OCI labels" || fail "  $(basename $f) missing LABEL"
            grep -q "VOLUME" "$f" && pass "  $(basename $f) has VOLUME" || fail "  $(basename $f) missing VOLUME"
        else
            fail "$(basename $f) missing"
        fi
    done

    header "Gitignore Rules"
    grep -q "^\.env$" .gitignore && pass ".env is gitignored" || fail ".env not gitignored"
    grep -q "^docker-compose\.yml$" .gitignore && pass "docker-compose.yml is gitignored" || fail "docker-compose.yml not gitignored"
    grep -q "backups/" .gitignore && pass "backups/ is gitignored" || fail "backups/ not gitignored"
    grep -q "\.claude/" .gitignore && pass "AI tool dirs gitignored" || fail "AI tool dirs not gitignored"

    header "No Hardcoded Secrets"
    if grep -rq "adminAccountBase64MD5=MD5:" docker/Dockerfile*; then
        fail "Hardcoded admin password found in Dockerfiles"
    else
        pass "No hardcoded passwords in Dockerfiles"
    fi

    header "No Stale References"
    if grep -rq "/api/status\.json" bin/ docker/ docker-compose*.yml --exclude="test.sh" 2>/dev/null; then
        fail "Stale /api/status.json reference found"
    else
        pass "No /api/status.json references"
    fi

    if grep -rq "/opt/stacks" bin/ *.md docker/ --exclude="test.sh" 2>/dev/null; then
        fail "Hardcoded /opt/stacks path found"
    else
        pass "No /opt/stacks paths"
    fi

    if grep -rq "\.env\.example" bin/ *.md docker-compose*.yml --exclude="test.sh" 2>/dev/null; then
        fail "Stale .env.example reference (should be .env_example)"
    else
        pass "No .env.example references"
    fi
}

# ============================================================
# Build Tests (requires Docker)
# ============================================================
test_build() {
    header "Docker Build (Alpine)"

    if ! command -v docker &> /dev/null; then
        skip "Docker not available"
        return
    fi

    if docker build -f docker/Dockerfile.alpine -t yacy:test-alpine \
        --build-arg YACY_VERSION=master \
        --build-arg BUILD_DATE="$(date -u +'%Y-%m-%dT%H:%M:%SZ')" \
        --build-arg YACY_SHA=test \
        . 2>&1 | tail -5; then
        pass "Alpine image builds successfully"

        # Check image labels
        VERSION=$(docker inspect yacy:test-alpine 2>/dev/null | jq -r '.[0].Config.Labels["org.opencontainers.image.version"]' 2>/dev/null)
        if [ -n "$VERSION" ] && [ "$VERSION" != "null" ]; then
            pass "OCI version label present: $VERSION"
        else
            fail "OCI version label missing"
        fi

        # Check non-root user
        USER=$(docker inspect yacy:test-alpine 2>/dev/null | jq -r '.[0].Config.User' 2>/dev/null)
        if [ "$USER" = "yacy" ]; then
            pass "Image runs as non-root user: $USER"
        else
            fail "Image user is '$USER', expected 'yacy'"
        fi
    else
        fail "Alpine image build failed"
    fi
}

# ============================================================
# Integration Tests (requires Docker, starts containers)
# ============================================================
test_integration() {
    header "Integration Tests"

    if ! command -v docker &> /dev/null; then
        skip "Docker not available"
        return
    fi

    # Ensure we have an image
    if ! docker image inspect yacy:latest > /dev/null 2>&1 && \
       ! docker image inspect yacy:test-alpine > /dev/null 2>&1; then
        skip "No yacy image available (run build tests first)"
        return
    fi

    # Use test-alpine if latest doesn't exist
    if ! docker image inspect yacy:latest > /dev/null 2>&1; then
        docker tag yacy:test-alpine yacy:latest
    fi

    # Set up standalone compose
    COMPOSE_FILE="$PROJECT_DIR/docker-compose.standalone.yml"

    echo "  Starting YaCy..."
    docker compose -f "$COMPOSE_FILE" up -d 2>&1 | tail -3

    # Wait for healthy
    echo "  Waiting for container to be healthy (up to 90s)..."
    ATTEMPT=0
    while [ $ATTEMPT -lt 18 ]; do
        if docker compose -f "$COMPOSE_FILE" ps 2>/dev/null | grep -q "healthy"; then
            break
        fi
        ATTEMPT=$((ATTEMPT + 1))
        sleep 5
    done

    if docker compose -f "$COMPOSE_FILE" ps 2>/dev/null | grep -q "healthy"; then
        pass "Container is healthy"
    else
        fail "Container did not become healthy"
        docker compose -f "$COMPOSE_FILE" logs --tail 20 yacy 2>&1
        docker compose -f "$COMPOSE_FILE" down 2>/dev/null
        return
    fi

    # Test web interface
    if curl -sf http://127.0.0.1:8090/ > /dev/null 2>&1; then
        pass "Web interface responding on port 8090"
    else
        fail "Web interface not responding"
    fi

    # Test hello endpoint
    if curl -sf http://127.0.0.1:8090/yacy/hello.html 2>/dev/null | grep -q "uptime="; then
        pass "YaCy hello endpoint returns peer info"
    else
        fail "Hello endpoint not working"
    fi

    # Test status.sh
    if ./bin/status.sh > /dev/null 2>&1; then
        pass "status.sh runs successfully"
    else
        fail "status.sh failed"
    fi

    # Test set-password.sh
    if ./bin/set-password.sh yacy testpass123 > /dev/null 2>&1; then
        pass "set-password.sh runs successfully"
    else
        fail "set-password.sh failed"
    fi

    # Test backup.sh
    if ./bin/backup.sh > /dev/null 2>&1; then
        pass "backup.sh runs successfully"
        BACKUP=$(ls -t backups/yacy_*.tar.gz 2>/dev/null | head -1)
        if [ -n "$BACKUP" ]; then
            pass "Backup file created: $(basename $BACKUP)"
        else
            fail "Backup file not found"
        fi
    else
        fail "backup.sh failed"
    fi

    # Test restore.sh (with -y to skip confirmation)
    if [ -n "$BACKUP" ]; then
        if ./bin/restore.sh -y "$BACKUP" > /dev/null 2>&1; then
            pass "restore.sh runs successfully"
            # Wait for healthy after restore
            ATTEMPT=0
            while [ $ATTEMPT -lt 18 ]; do
                if docker compose -f "$COMPOSE_FILE" ps 2>/dev/null | grep -q "healthy"; then
                    break
                fi
                ATTEMPT=$((ATTEMPT + 1))
                sleep 5
            done
            if docker compose -f "$COMPOSE_FILE" ps 2>/dev/null | grep -q "healthy"; then
                pass "Container healthy after restore"
            else
                fail "Container not healthy after restore"
            fi
        else
            fail "restore.sh failed"
        fi
    else
        skip "restore.sh (no backup file to test with)"
    fi

    # Cleanup
    echo "  Cleaning up..."
    docker compose -f "$COMPOSE_FILE" down 2>/dev/null
}

# ============================================================
# Main
# ============================================================
MODE="${1:-unit}"

echo ""
echo "YaCy Docker Stack - Test Suite"
echo "Mode: $MODE"

case "$MODE" in
    unit)
        test_unit
        ;;
    build)
        test_build
        ;;
    integration)
        test_integration
        ;;
    all)
        test_unit
        test_build
        test_integration
        ;;
    *)
        echo "Usage: $0 [unit|build|integration|all]"
        exit 1
        ;;
esac

# Summary
echo ""
echo -e "${YELLOW}=== Results ===${NC}"
echo -e "  ${GREEN}Passed: $PASS${NC}"
[ $FAIL -gt 0 ] && echo -e "  ${RED}Failed: $FAIL${NC}" || echo "  Failed: 0"
[ $SKIP -gt 0 ] && echo -e "  ${YELLOW}Skipped: $SKIP${NC}"
echo ""

[ $FAIL -gt 0 ] && exit 1 || exit 0
