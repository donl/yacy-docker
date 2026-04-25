# Architecture Notes

Design decisions and rationale for this YaCy Docker stack.

---

## Build System

### Multi-Architecture Dockerfiles

Separate Dockerfiles per platform because each needs different base images and Java versions:

| Variant | Base | Java | Size | Notes |
|---------|------|------|------|-------|
| Dockerfile | eclipse-temurin:24-jdk-noble | 24 | ~500MB | Full apt ecosystem |
| Dockerfile.alpine | eclipse-temurin:21-jdk-alpine | 21 | ~200MB | No wkhtmltopdf available |
| Dockerfile.aarch64 | eclipse-temurin:21-jdk-noble | 21 | ~450MB | Raspberry Pi 4+, ARM cloud |
| Dockerfile.armv7 | arm32v7/openjdk:11 | 11 | ~350MB | Java 11 EOL Oct 2026 |

A single multi-platform Dockerfile was considered but rejected -- different package managers (apt vs apk), different Java availability, and different optimization targets make separate files cleaner.

### Multi-Stage Builds

Builder stage (JDK + ant + git) compiles from source. Final stage copies the result into a JRE-only image. Saves ~100-200MB per image by excluding build tools from the runtime.

### Layer Caching Strategy

```dockerfile
# Dependencies installed FIRST (rarely change, cached)
RUN apt-get install -y ant git curl

# Version ARG placed AFTER dependencies
ARG YACY_VERSION=master

# Source clone + build (invalidated on version change, but apt cache preserved)
RUN git clone --depth 1 --branch ${YACY_VERSION} ...
```

This ordering means rebuilding with the same version takes ~15 seconds (cached deps). Rebuilding with a new version takes ~2 minutes (fresh clone, cached deps). Putting the ARG first would invalidate everything on every version change.

### Git-Based Versioning

Images build from GitHub releases/commits via `git clone --depth 1 --branch`, not from local source. This means:
- Reproducible builds tied to specific tags/commits
- No need to clone the full YaCy repo locally
- `build.sh` queries the GitHub API to let you pick a version interactively

---

## Deployment

### Reverse Proxy Options

Three compose templates for different setups:

- `docker-compose.traefik.yml` -- Traefik with Let's Encrypt
- `docker-compose.caddy.yml` -- Caddy with Docker provider labels
- `docker-compose.standalone.yml` -- No proxy, localhost:8090 only

Users copy their choice to `docker-compose.yml` (gitignored). Traefik/Caddy templates use named external networks (`traefik-network` / `caddy-network`).

### No External Database

YaCy is self-contained. It has a built-in Solr index and file-based storage. An optional external Solr service is available via `docker-compose.solr.yml` overlay for federated search, but it's not required.

### Named Volumes

Data lives in Docker named volumes (`yacy_data`), not bind mounts. This keeps the project directory clean and makes backups/restores work consistently via `docker run --rm -v yacy_data:/data alpine tar ...`.

---

## Security

Summary of security posture. See [SECURITY.md](SECURITY.md) for the full policy.

- **Non-root execution**: Container runs as `yacy` user
- **No default credentials**: Admin password must be set post-deploy
- **Network isolation**: Only exposed ports are 8090/8443, routed through reverse proxy
- **Security headers**: X-Frame-Options, X-Content-Type-Options, XSS-Protection via Caddy labels
- **Health checks**: `/` endpoint, 30s interval, 60s start period
- **Log rotation**: JSON file driver, 200MB max, 2 files

---

## OCI Image Labels

Standard `org.opencontainers.image.*` labels for version tracking:

```dockerfile
LABEL org.opencontainers.image.version="${YACY_VERSION} (${YACY_SHA})"
      org.opencontainers.image.created="${BUILD_DATE}"
      org.opencontainers.image.source="https://github.com/yacy/yacy_search_server"
```

`./bin/status.sh` reads these to show the running version and build date.

---

## Future Considerations

- **Kubernetes**: Helm chart or kustomize manifests
- **Metrics**: Prometheus endpoint for monitoring
- **Multi-instance**: YaCy peer federation across containers
- **ARM32 deprecation**: Java 11 EOL is October 2026

---

## References

- [Docker best practices](https://docs.docker.com/develop/dev-best-practices/)
- [OCI Image Spec labels](https://github.com/opencontainers/image-spec/blob/main/annotations.md)
- [YaCy documentation](https://yacy.net/)
