# Security Policy & Guidelines

## Vulnerability Reporting

If you discover a security vulnerability, **please do not open a public issue**. Instead:

1. **Email details** to the maintainers (ideally with PGP key if available)
2. **Include**:
   - Description of the vulnerability
   - Steps to reproduce
   - Potential impact
   - Suggested fix (if you have one)

3. **Timeline**:
   - We'll acknowledge receipt within 48 hours
   - We'll provide status updates
   - We aim to patch within 7-14 days depending on severity

---

## Security Considerations

### Built-In Protections

#### 1. Non-Root User
- YaCy runs as unprivileged `yacy` user
- Container escape would not grant host root access
- Limits privilege escalation surface

#### 2. Security Headers (Caddy)
The Caddy compose template includes these response headers:
```
X-Frame-Options: SAMEORIGIN
X-Content-Type-Options: nosniff
X-XSS-Protection: 1; mode=block
Referrer-Policy: strict-origin-when-cross-origin
```
Add HSTS and additional headers via your reverse proxy config as needed.

#### 3. HTTPS/TLS
- Automatic certificate management via Let's Encrypt
- HTTPS enforced, HTTP to HTTPS redirect
- Strong cipher suites (Traefik default)

#### 4. No Default Credentials
- Admin password must be set manually
- `bin/set-password.sh` helper for automation
- Prevents "default password" attacks

#### 5. Health Checks
- REST API endpoint validates liveness
- Detects hung or broken processes
- Stuck containers automatically detected

### Network Security

#### Isolation
- Containers isolated from host by default
- Only specified ports exposed
- YaCy internal ports not accessible from host

#### Multi-Network Mode
```yaml
networks:
  - default    # Internal only
  - traefik-network   # Reverse proxy access only (or caddy-network)
```

#### Firewall Rules
When deployed behind Traefik:
- Port 8090 (HTTP) → Not exposed to host
- Port 8443 (HTTPS) → Not exposed to host
- All traffic → Through reverse proxy
- Reverse proxy → Firewall rules apply

### Data Security

#### Backup Encryption
**Current state**: Backups are NOT encrypted by default.

**Recommendation for production**:
```bash
# Encrypt backups
./bin/backup.sh && openssl enc -aes-256-cbc -in backups/yacy_latest.tar.gz -out backups/yacy_latest.tar.gz.enc

# Decrypt for restore
openssl enc -aes-256-cbc -d -in backup.tar.gz.enc | tar -xzf -
```

**Better approach for sensitive data**:
```bash
# Use GPG encryption
./bin/backup.sh && gpg --encrypt --recipient you@example.com backups/yacy_latest.tar.gz

# Decrypt
gpg --decrypt backup.tar.gz.gpg | tar -xzf -
```

#### Volume Permissions
- Named volumes owned by `yacy` user
- Only readable by container
- Host permissions restrict access

#### Data at Rest
- Stored in Docker named volume (default: `/var/lib/docker/volumes/`)
- No encryption by default
- Consider encrypted filesystem for high-security deployments

### Dependency Security

#### Image Scanning
Regular updates recommended:

```bash
# Check image for vulnerabilities
docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
  aquasec/trivy image yacy:latest

# Or using Grype
grype yacy:latest
```

#### Base Image Updates
- Temurin images regularly patched
- Alpine images lightweight but regularly updated
- Monitor release notes: https://github.com/eclipse-temurin/temurin-docker

#### Dependency Management
- No custom package installations
- Only official base images used
- Minimal attack surface

---

## Security Hardening

### For Production Deployments

#### 1. Secrets Management
```bash
# DO NOT: Hardcode secrets
.env file → git-ignored, never committed

# DO: Use environment variables
source /secure/location/.env
docker compose up -d

# BETTER: Use Docker Secrets (Swarm) or external vault
docker secret create yacy_password -
docker service create \
  --secret yacy_password \
  image:tag
```

#### 2. TLS Configuration
```bash
# Verify certificate validity
curl -I https://yacy.example.com

# Check certificate details
openssl s_client -connect yacy.example.com:443
```

#### 3. Firewall Rules
```bash
# Only allow HTTPS (443) from trusted IPs
iptables -A INPUT -p tcp --dport 443 -s 10.0.0.0/8 -j ACCEPT
iptables -A INPUT -p tcp --dport 443 -j DROP

# Block direct access to container ports
iptables -A INPUT -p tcp --dport 8090 -j DROP
iptables -A INPUT -p tcp --dport 8443 -j DROP
```

#### 4. Log Monitoring
```bash
# Monitor for suspicious activity
docker compose logs yacy | grep -i "error\|unauthorized\|forbidden"

# Set up ELK stack or similar for centralized logging
```

#### 5. Regular Updates
```bash
# Check for image updates
docker compose pull

# Rebuild with latest base images
DOCKER_BUILDKIT=1 ./bin/build.sh

# Or on schedule
0 2 * * 0 cd /path/to/yacy && docker compose pull && ./bin/build.sh
```

### For Secure Development

#### 1. Git Configuration
```bash
# Sign commits
git config user.signingkey YOUR_GPG_KEY
git commit -S -m "message"

# Verify signatures
git verify-commit HEAD
```

#### 2. Code Review
- All changes reviewed before merge
- Security-focused code review checklist
- No hardcoded secrets in any commits

#### 3. Dependency Auditing
```bash
# Check Docker images for vulnerabilities
trivy image yacy:latest

# Keep base images updated
docker pull eclipse-temurin:24-jdk-noble
docker pull alpine:latest
```

---

## Common Security Mistakes

### ❌ DON'T

1. **Commit .env file**
   ```bash
   # BAD
   git add .env
   git commit -m "add config"
   ```

2. **Hardcode credentials**
   ```dockerfile
   # BAD
   ENV ADMIN_PASSWORD="password123"
   RUN sed -i "s/PASSWORD/$ADMIN_PASSWORD/" config.ini
   ```

3. **Run as root in container**
   ```dockerfile
   # BAD - Don't do this
   USER root
   CMD [...yacy...]
   ```

4. **Expose unnecessary ports**
   ```yaml
   # BAD
   ports:
     - "8090:8090"    # Exposes to 0.0.0.0
     - "8443:8443"
   ```

5. **Skip health checks**
   ```dockerfile
   # BAD - Remove this
   HEALTHCHECK NONE
   ```

6. **Trust unverified images**
   ```bash
   # BAD
   docker pull random-yacy:latest
   docker compose up
   ```

### ✅ DO

1. **Use .env with .gitignore**
   ```bash
   cp .env_example .env
   # .gitignore includes: .env
   ```

2. **Set passwords at runtime**
   ```bash
   ./bin/set-password.sh yacy secure_password_123
   ```

3. **Run as non-root user**
   ```dockerfile
   RUN adduser --system yacy
   USER yacy
   CMD [...yacy...]
   ```

4. **Restrict port exposure**
   ```yaml
   expose:
     - "8090"  # Not exposed to host
   # Access through reverse proxy only
   ```

5. **Always include health checks**
   ```dockerfile
   HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
     CMD curl -f http://localhost:8090/ || exit 1
   ```

6. **Verify image provenance**
   ```bash
   # Use official images with signatures
   docker image inspect yacy:latest | grep -i "RepoTags\|Architecture"
   ```

---

## Security Audit Checklist

Before deploying to production, verify:

### Container Security
- [ ] Running as non-root user
- [ ] Health checks configured
- [ ] No hardcoded secrets in Dockerfile
- [ ] No unnecessary ports exposed
- [ ] Image scanned for vulnerabilities (`trivy image`)

### Network Security
- [ ] HTTPS enabled and enforced
- [ ] Certificate valid and non-expired
- [ ] Security headers present (HSTS, CSP, etc.)
- [ ] Firewall rules restrict access
- [ ] Only required ports open (80, 443)

### Data Security
- [ ] Backups encrypted (GPG or openssl)
- [ ] Backups tested for recoverability
- [ ] Volume permissions restricted
- [ ] Sensitive data not in logs
- [ ] `.env` files in `.gitignore`

### Operational Security
- [ ] Only trusted images used
- [ ] Base images regularly updated
- [ ] Security patches applied promptly
- [ ] Logs monitored for anomalies
- [ ] Admin password strong and unique
- [ ] Backup locations secure

---

## Incident Response

### If Compromise is Suspected

1. **Isolate**
   ```bash
   docker compose stop yacy
   docker network disconnect traefik-network yacy
   ```

2. **Preserve Evidence**
   ```bash
   docker compose logs yacy > incident_$(date +%s).log
   docker inspect yacy > container_state.json
   ```

3. **Investigate**
   ```bash
   # Check for unauthorized changes
   docker exec yacy ls -la /opt/yacy_search_server/defaults/
   docker exec yacy cat /opt/yacy_search_server/defaults/yacy.init
   ```

4. **Remediate**
   ```bash
   # If credential compromise
   ./bin/set-password.sh yacy new_strong_password_123
   docker compose restart yacy
   
   # If code compromise
   docker compose down
   docker volume rm yacy_yacy_data  # If compromised
   docker compose up -d  # Restore from backup
   ```

5. **Notify**
   - Inform stakeholders
   - Document timeline
   - Plan post-incident review

---

## Resources

- [OWASP Container Security](https://cheatsheetseries.owasp.org/cheatsheets/Docker_Security_Cheat_Sheet.html)
- [CIS Docker Benchmark](https://www.cisecurity.org/cis-benchmarks/)
- [Docker Security Best Practices](https://docs.docker.com/engine/security/)
- [Container Image Scanning](https://aquasecurity.github.io/trivy/)

For security issues, contact maintainers privately (see top of this document).
