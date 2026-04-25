# YaCy Search Server - Docker Stack

YaCy is a decentralized search engine and web crawler. This stack provides Docker configurations for deploying YaCy with automated backups and reverse proxy support (Traefik or Caddy).

---

## Quick Start

### Prerequisites
- Docker & Docker Compose
- ~2GB disk space minimum
- Ports 8090/8443 only needed for standalone mode (reverse proxy handles routing otherwise)
- Utilities: `jq`, `curl`, `tar` (install via `apt-get install jq curl tar`)

### 1. Configure
```bash
# Copy template configuration
cp .env_example .env

# Edit with your domain
nano .env
# Required: Set YACY_DOMAIN=yacy.example.com
```

### 2. Get Image

**Option A: Pull pre-built from GitHub Container Registry**
```bash
docker pull ghcr.io/donl/yacy-docker:alpine    # x86_64, ~200MB
docker pull ghcr.io/donl/yacy-docker:debian    # x86_64, ~500MB
docker pull ghcr.io/donl/yacy-docker:aarch64   # ARM64 (Pi 4+)
docker pull ghcr.io/donl/yacy-docker:armv7     # ARM32 (Pi 2/3)

# Tag for local use
docker tag ghcr.io/donl/yacy-docker:alpine yacy:latest
```

**Option B: Build locally (custom version selection)**
```bash
./bin/build.sh

# Prompts you to select:
# 1. Architecture (Debian/Ubuntu, Alpine, ARM64, ARM32)
# 2. Version (releases, commits, or master branch)
# build.sh will prompt for version selection interactively
```

### 3. Choose Deployment

Copy your preferred compose template to `docker-compose.yml`:

```bash
# Traefik (recommended for production)
cp docker-compose.traefik.yml docker-compose.yml

# Caddy (alternative reverse proxy)
cp docker-compose.caddy.yml docker-compose.yml

# Standalone (local only, no reverse proxy)
cp docker-compose.standalone.yml docker-compose.yml
```

`docker-compose.yml` is gitignored -- it's your local deployment config.

### 4. Start Service

```bash
docker compose up -d
```

Verify:
```bash
# Wait for healthy status (~30s)
docker compose ps
# STATUS should show: (healthy)

# Check logs
docker compose logs -f yacy
```

### 5. Access YaCy
- **Web Interface**: http://localhost:8090
- **Initial Setup**: No default password (set on first login)
- **With Traefik/Caddy**: https://yacy.yourdomain.com

### 6. Set Admin Password
```bash
# Set password in running container
./bin/set-password.sh yacy mynewpassword

# Or via web UI:
# 1. Go to http://localhost:8090
# 2. Settings > Access > Admin Password
# 3. Set your password
```

### 7. Monitor Status (Optional)
```bash
# Check version, uptime, resource usage, disk space
./bin/status.sh

# Shows version, uptime, resources, disk, health
```

---

## Deployment Options

### Compose Templates

Copy one of these to `docker-compose.yml` for your setup:

| Template | Reverse Proxy | HTTPS | Network |
|----------|---------------|-------|---------|
| `docker-compose.traefik.yml` | Traefik | Auto (Let's Encrypt) | External `traefik-network` |
| `docker-compose.caddy.yml` | Caddy | Auto (Let's Encrypt) | External `caddy-network` |
| `docker-compose.standalone.yml` | None | No | Localhost only |

`docker-compose.yml` is gitignored -- your local deployment choice.

---

## Configuration

### Environment Variables (`.env`)

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `YACY_DOMAIN` | ✅ | N/A | Domain for Traefik/HTTPS (e.g., yacy.example.com) |
| `YACY_VERSION` | ❌ | `master` | Git tag/release/branch (e.g., Release_1.941) |
| `JAVA_OPTS` | ❌ | `-Xmx2048m -Xms512m` | JVM memory settings |
| `BACKUP_DIR` | ❌ | `./backups` | Backup storage directory |
| `BACKUP_RETENTION_DAYS` | ❌ | `7` | Days to keep backups |
| `TZ` | ❌ | `UTC` | Container timezone |


---

## Available Scripts

All scripts are in `./bin/` directory:

### `build.sh` - Interactive Image Builder
```bash
./bin/build.sh
```
- Fetches releases/commits from GitHub API
- Interactive version selection
- Builds with proper architecture tagging
- Supports GitHub token for higher rate limits: `GITHUB_TOKEN=ghp_... ./bin/build.sh`

### `set-password.sh` - Set Admin Password
```bash
./bin/set-password.sh [container-name] [password]

# Examples:
./bin/set-password.sh yacy mypassword
./bin/set-password.sh yacy_prod securepassword123
```

### `backup.sh` - Automated Backups
```bash
# Manual backup
./bin/backup.sh

# Cron (daily at 2 AM)
0 2 * * * /path/to/yacy/bin/backup.sh >> /var/log/yacy-backup.log 2>&1
```
- Backs up to `./backups/yacy_YYYYMMDD_HHMMSS.tar.gz`
- Keeps 7 days of backups (configurable via BACKUP_RETENTION_DAYS)

### `restore.sh` - Restore from Backup
```bash
./bin/restore.sh ./backups/yacy_20260425_000000.tar.gz
```
- Confirms before overwriting data
- Validates backup format
- Restarts container and verifies health

### `solr-init.sh` - Solr Integration Setup
```bash
./bin/solr-init.sh
```
- Creates `collection1` and `webgraph` cores with YaCy's schema
- Configures YaCy to use external Solr (`yacy.conf`)
- Run after starting the Solr overlay: `ln -s docker-compose.solr.yml docker-compose.override.yml`

### `status.sh` - System Status & Health Check
```bash
./bin/status.sh
```
Shows container status, version/build info, CPU/memory, volume size, health, and Solr cores (if enabled).

---

## Directory Structure

```
yacy/
├── README.md                    # This file
├── docker-compose.yml          # Your deployment (created from template, gitignored)
├── docker-compose.traefik.yml  # Template: Traefik reverse proxy
├── docker-compose.caddy.yml    # Template: Caddy reverse proxy
├── docker-compose.standalone.yml # Template: Local only, no proxy
├── .env                        # Configuration (NOT committed)
├── .env_example               # Configuration template (committed)
│
├── bin/                        # Scripts (executable)
│   ├── build.sh              # Interactive image builder
│   ├── status.sh             # Health & resource monitoring
│   ├── set-password.sh       # Admin password setter
│   ├── backup.sh             # Backup tool
│   ├── restore.sh            # Restore tool
│   └── solr-init.sh          # Solr collection setup
│
├── docker/                    # Dockerfiles
│   ├── Dockerfile           # Ubuntu/Debian (default, 24-jdk, ~500MB)
│   ├── Dockerfile.alpine    # Alpine (lightweight, 21-jdk, ~200MB)
│   ├── Dockerfile.aarch64   # ARM64 (23-jdk, ~450MB)
│   └── Dockerfile.armv7     # ARM32 (11-jdk, ~350MB)
│
└── backups/                  # Backup archives (NOT committed)
    └── yacy_YYYYMMDD_HHMMSS.tar.gz

# Note: YaCy data is stored in Docker named volumes (yacy_data),
# not in a local data/ directory. Use ./bin/status.sh to check size.
```

---

## Build Architecture Variants

### Dockerfile (Ubuntu/Debian) - Default
- **Base**: `eclipse-temurin:24-jdk-noble`
- **Size**: ~500MB
- **Best For**: General-purpose, cloud servers
- **Features**: Latest Java 24, full apt package ecosystem

### Dockerfile.alpine - Recommended ⭐
- **Base**: `eclipse-temurin:21-jdk-alpine`
- **Size**: ~200MB (60% smaller)
- **Best For**: Production, registries, resource-constrained
- **Tradeoff**: No wkhtmltopdf (PDF rendering disabled)

### Dockerfile.aarch64 - ARM64
- **Base**: `arm64v8/openjdk:23`
- **Size**: ~450MB
- **Best For**: Raspberry Pi 4+, ARM cloud instances
- **Java**: 23 (good ARM64 support)

### Dockerfile.armv7 - ARM32
- **Base**: `arm32v7/openjdk:11`
- **Size**: ~350MB
- **Best For**: Raspberry Pi 2/3, legacy ARM devices
- **Java**: 11 LTS (only compatible with ARM32)

---

## Common Tasks

### Change YaCy Version
```bash
# Edit .env and change YACY_VERSION
nano .env

# Rebuild image
./bin/build.sh
# build.sh will prompt for version selection interactively

# Restart service
docker compose up -d --pull never
```

### Check System Status & Health
```bash
# Comprehensive status report
./bin/status.sh

# Shows: version, uptime, resource usage, disk space, health
```

### View Logs
```bash
# Real-time logs
docker compose logs -f yacy

# Last 50 lines
docker compose logs --tail 50 yacy

# Full log with timestamps
docker compose logs --timestamps yacy
```

### Access YaCy Admin Panel
```bash
# Via HTTP (local)
http://localhost:8090

# Via HTTPS (with Traefik/Caddy)
https://yacy.yourdomain.com

# From container
docker exec -it yacy curl http://localhost:8090/yacy/hello.html
```

### Check Crawler Status
```bash
docker exec -it yacy curl http://localhost:8090/api/crawlstatus.json | jq .
```

### Increase Memory for Large Crawls
```bash
# Edit .env
JAVA_OPTS="-Xmx4096m -Xms1024m"

# Restart
docker compose up -d
```

---

## Troubleshooting

### Container Won't Start
```bash
# Check logs
docker compose logs yacy

# Verify .env exists and is complete
cat .env | grep "^[^#]"

# Check disk space
docker system df

# Verify port isn't in use
lsof -i :8090
```

### High Memory Usage
```bash
# Current usage
docker stats yacy

# Reduce memory in .env
JAVA_OPTS="-Xmx1024m -Xms512m"

# Restart
docker compose restart yacy
```

### Backup Fails
```bash
# Verify backup directory exists
mkdir -p ./backups

# Check permissions
ls -la ./backups

# Test manually
docker run --rm -v yacy_data:/data alpine ls -la /data
```

### Restore Fails
```bash
# Verify backup file exists and is readable
ls -lh ./backups/yacy_*.tar.gz

# Check integrity
tar -tzf ./backups/yacy_20260425_000000.tar.gz | head

# Restore
./bin/restore.sh ./backups/yacy_20260425_000000.tar.gz
```

### Alpine Variant Missing wkhtmltopdf
```bash
# If PDF rendering is needed, rebuild with Ubuntu variant:
./bin/build.sh
# Select: [1] Debian/Ubuntu (instead of Alpine)

# build.sh tags the image as yacy:latest automatically

# Restart
docker compose up -d
```

### GitHub API Rate Limiting
```bash
# If build.sh fails with "Could not fetch data from GitHub API":
# Option 1: Wait 1 hour
# Option 2: Use GitHub token for higher limits
export GITHUB_TOKEN=ghp_your_token_here
./bin/build.sh
```

---

## Networking & Security

### Local Only (Default)
```yaml
# docker-compose.yml
ports:
  - "127.0.0.1:8090:8090"  # localhost only
```

### With Traefik Reverse Proxy
```bash
# Requires:
# - YACY_DOMAIN set in .env
# - Traefik stack running (with traefik-network Docker network)
# - DNS pointing to Traefik server

# Automatic HTTPS, routing, and security headers
```

### Admin Panel Security
- **Default**: No default credentials (set on first login)
- **Recommended**: Use strong password (20+ characters)
- **HTTPS**: Enable via Traefik for production

---

## Performance Tuning

### For Heavy Crawling
```bash
# .env
JAVA_OPTS="-Xmx4096m -Xms2048m -XX:+UseG1GC -XX:MaxGCPauseMillis=200"

# docker-compose.yml
cpus: "3.0"
memory: 5GB
```

### For Small Servers
```bash
# .env
JAVA_OPTS="-Xmx512m -Xms256m"

# Use Alpine variant for smallest footprint
```

### Caching Optimization
```bash
# For frequently rebuilt images:
export DOCKER_BUILDKIT=1
./bin/build.sh

# Rebuilds with same version use cached layers (~10-15 sec)
```

---

## Backup & Recovery Strategy

### Daily Backups
```bash
# Add to crontab
0 2 * * * /path/to/yacy/bin/backup.sh >> /var/log/yacy-backup.log 2>&1

# Keeps 7 days automatically
# Location: ./backups/
```

### Disaster Recovery
```bash
# Restore latest backup
LATEST=$(ls -t ./backups/yacy_*.tar.gz | head -1)
./bin/restore.sh "$LATEST"
```

### Testing Backups
```bash
# Verify backup integrity monthly
tar -tzf ./backups/yacy_latest.tar.gz | head -20
```

---

## Advanced Topics

### Building from Specific Commit
```bash
./bin/build.sh
# Select: [1-6] (commits section)
# Choose specific commit by SHA
```

### Custom YaCy Configuration
```bash
# Edit via web UI:
# Settings > Configure > Admin Password
# Settings > Configure > Port Configuration

# Or edit config inside the container:
# docker exec -it yacy vi /opt/yacy_search_server/DATA/SETTINGS/yacy.conf
# docker compose restart yacy
```

### Enabling HTTPS Directly
```bash
# Without Traefik, enable in YaCy config:
# Settings > Network > Server HTTPS

# Note: Self-signed certificates by default
# Use Traefik for proper HTTPS management
```

---

## Documentation

- **Official YaCy**: https://yacy.net/
- **GitHub**: https://github.com/yacy/yacy_search_server
- **Docker Docs**: https://docs.docker.com/
- **Traefik**: https://doc.traefik.io/traefik/
- **Caddy**: https://caddyserver.com/docs/

---

## Support & Issues

### Getting Help
1. Check logs: `docker compose logs yacy`
2. Review troubleshooting section above
3. Check official YaCy documentation
4. See GitHub issues: https://github.com/yacy/yacy_search_server/issues

### Reporting Issues
Include:
- Docker version: `docker --version`
- Compose version: `docker compose version`
- OS/Architecture: `uname -a`
- Relevant logs: `docker compose logs yacy`
- Steps to reproduce

---

## License

YaCy is licensed under LGPL. See https://github.com/yacy/yacy_search_server/blob/master/LICENSE

This Docker configuration is provided under the MIT license. YaCy itself is LGPL.
