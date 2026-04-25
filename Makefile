.PHONY: help build start stop restart status logs clean backup restore
.PHONY: standalone caddy traefik compose-valid health test version

# Default target
help:
	@echo "YaCy Docker Stack - Common Operations"
	@echo ""
	@echo "Building:"
	@echo "  make build              Interactive image build with version selection"
	@echo "  make build-alpine       Build Alpine variant"
	@echo "  make build-aarch64      Build ARM64 variant"
	@echo "  make build-armv7        Build ARM32 variant"
	@echo ""
	@echo "Starting Services:"
	@echo "  make start              Start YaCy (default Traefik setup)"
	@echo "  make standalone         Start YaCy standalone (localhost:8090)"
	@echo "  make caddy              Start YaCy with Caddy"
	@echo "  make traefik            Start YaCy with generic Traefik"
	@echo ""
	@echo "Managing Services:"
	@echo "  make stop               Stop YaCy container"
	@echo "  make restart            Restart YaCy"
	@echo "  make status             Show status, version, resources"
	@echo "  make logs               View real-time logs"
	@echo "  make health             Check container health"
	@echo ""
	@echo "Backup & Recovery:"
	@echo "  make backup             Create backup"
	@echo "  make restore            Restore from backup (interactive)"
	@echo "  make test-backup        Verify latest backup integrity"
	@echo ""
	@echo "Configuration:"
	@echo "  make set-password       Set admin password"
	@echo "  make set-password-prod  Set admin password (production)"
	@echo ""
	@echo "System:"
	@echo "  make version            Show script versions"
	@echo "  make validate           Validate docker-compose files"
	@echo "  make clean              Remove stopped containers & dangling images"
	@echo ""
	@echo "Development:"
	@echo "  make shell              Shell into running container"
	@echo "  make ps                 Show container status"
	@echo "  make df                 Show disk usage"
	@echo ""

# --- Building ---

build:
	@./bin/build.sh

build-alpine:
	@printf '2\nm\n' | ./bin/build.sh

build-aarch64:
	@printf '3\nm\n' | ./bin/build.sh

build-armv7:
	@printf '4\nm\n' | ./bin/build.sh

# --- Starting ---

start:
	@docker compose up -d
	@echo ""
	@./bin/status.sh

standalone:
	@echo "Starting YaCy (Standalone mode, localhost:8090)..."
	@docker compose -f docker-compose.standalone.yml up -d
	@echo ""
	@./bin/status.sh

caddy:
	@echo "Starting YaCy (Caddy mode)..."
	@docker compose -f docker-compose.caddy.yml up -d
	@echo ""
	@./bin/status.sh

traefik:
	@echo "Starting YaCy (Generic Traefik mode)..."
	@docker compose -f docker-compose.traefik.yml up -d
	@echo ""
	@./bin/status.sh

# --- Managing ---

stop:
	@echo "Stopping YaCy..."
	@docker compose stop

restart:
	@echo "Restarting YaCy..."
	@docker compose restart
	@echo "Waiting for health check..."
	@sleep 5
	@./bin/status.sh

status:
	@./bin/status.sh

logs:
	@docker compose logs -f yacy

health:
	@echo "Checking YaCy health..."
	@docker exec yacy curl -s http://localhost:8090/yacy/hello.html

# --- Backup & Recovery ---

backup:
	@./bin/backup.sh

restore:
	@LATEST=$$(ls -t $${BACKUP_DIR:-./backups}/yacy_*.tar.gz 2>/dev/null | head -1); \
	if [ -z "$$LATEST" ]; then \
		echo "No backups found in $${BACKUP_DIR:-./backups}/"; \
		exit 1; \
	fi; \
	echo "Latest backup: $$LATEST"; \
	./bin/restore.sh "$$LATEST"

test-backup:
	@echo "Testing latest backup..."
	@LATEST=$$(ls -t $${BACKUP_DIR:-./backups}/yacy_*.tar.gz 2>/dev/null | head -1); \
	if [ -z "$$LATEST" ]; then \
		echo "No backups found"; \
		exit 1; \
	fi; \
	echo "Testing: $$LATEST"; \
	tar -tzf "$$LATEST" | head -20 && echo "✓ Backup is valid"

# --- Configuration ---

set-password:
	@echo "Enter admin password: "
	@read -s PASSWORD; \
	./bin/set-password.sh yacy "$$PASSWORD"

set-password-prod:
	@echo "Enter production container name (default: yacy): "
	@read -r CONTAINER; \
	CONTAINER=$${CONTAINER:-yacy}; \
	echo "Enter admin password for $$CONTAINER: "; \
	read -s PASSWORD; \
	echo ""; \
	./bin/set-password.sh "$$CONTAINER" "$$PASSWORD"

# --- System ---

version:
	@echo "YaCy Docker Stack - Script Versions"
	@echo ""
	@for script in bin/*.sh; do \
		echo "$$(basename $$script):"; \
		head -2 $$script | tail -1 | sed 's/# /  /'; \
	done

validate:
	@echo "Validating docker-compose files..."
	@for file in docker-compose*.yml; do \
		echo "Checking $$file..."; \
		docker compose -f $$file config > /dev/null && echo "  ✓ Valid" || echo "  ✗ Invalid"; \
	done

clean:
	@echo "Cleaning up Docker resources..."
	@docker container prune -f
	@docker image prune -f
	@echo "Done!"

# --- Development ---

shell:
	@echo "Opening shell in yacy container..."
	@docker exec -it yacy /bin/sh

ps:
	@docker compose ps

df:
	@echo "Disk usage (yacy_data volume):"
	@docker run --rm -v yacy_data:/data alpine du -sh /data 2>/dev/null || echo "Volume not found"
	@echo ""
	@echo "Image size:"
	@docker image ls yacy --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}" 2>/dev/null || echo "No yacy image"

# --- Utilities ---

compose-valid:
	@docker compose config > /dev/null && echo "✓ docker-compose.yml is valid"

watch:
	@watch -n 2 'docker compose ps && echo "" && docker compose logs --tail=10 yacy'

api-status:
	@curl -s http://localhost:8090/yacy/hello.html

test: validate compose-valid
	@echo "Running basic tests..."
	@docker compose up -d
	@sleep 5
	@docker compose ps
	@./bin/status.sh
	@echo "✓ Basic tests passed"

# --- Info ---

readme:
	@cat README.md | head -50

architecture:
	@cat ARCHITECTURE.md | head -50

security:
	@cat SECURITY.md | head -50

.PHONY: all
all: help
