# Contributing

Guidelines for contributing to this stack.

## Reporting Issues

Open an issue with:
- OS, Docker, and Compose versions
- Steps to reproduce
- Relevant logs (`docker compose logs yacy`)

## Code Changes

1. Open an issue first for major changes
2. Branch from main: `git checkout -b feature/your-feature`
3. Test: `./bin/build.sh && docker compose up -d && ./bin/status.sh`
4. Commit with conventional format: `feat:`, `fix:`, `docs:`, `chore:`
5. Open a PR

### Dockerfile changes
- Test layer caching (build twice -- second should be fast)
- Verify health checks still pass
- Note architecture-specific considerations

### Shell scripts
- `set -e` at top
- Check dependencies before using them
- Meaningful error messages

## Testing Checklist

Before submitting:

- [ ] `docker compose up -d` starts clean
- [ ] `./bin/status.sh` shows healthy
- [ ] No hardcoded secrets or credentials
- [ ] Docs updated if user-facing

## Security Issues

See [SECURITY.md](SECURITY.md) for reporting vulnerabilities.

## Code of Conduct

Be respectful. Focus on the work.
