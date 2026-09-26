#!/bin/bash
set -euo pipefail

LOG_FILE="/opt/apps/disk-cleanup.log"

log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >> "$LOG_FILE"
}

log "=== Starting disk cleanup ==="
log "Before: $(df -h / | awk 'NR==2 {print $3" used, "$4" free, "$5" full"}')"

# Docker build cache — safe, only removes cache layers not tied to any image.
docker builder prune -f >> "$LOG_FILE" 2>&1 || log "docker builder prune failed"

# Stopped containers older than 24h — safe, running containers are untouched.
docker container prune -f --filter "until=24h" >> "$LOG_FILE" 2>&1 || log "docker container prune failed"

# Dangling images only (untagged, not referenced by any container) — never touches
# an image that's still tagged/in use, so running services are unaffected.
docker image prune -f >> "$LOG_FILE" 2>&1 || log "docker image prune failed"

# Journal logs beyond 200M.
sudo journalctl --vacuum-size=200M >> "$LOG_FILE" 2>&1 || log "journalctl vacuum failed"

# APT package cache.
sudo apt-get clean >> "$LOG_FILE" 2>&1 || log "apt-get clean failed"

# Leftover scratch clones/worktrees from agent sessions, if untouched for 2+ days.
find /tmp -maxdepth 1 -type d \( -iname "*-seo-fix" -o -iname "*-scratch" \) -mtime +2 -exec rm -rf {} + 2>>"$LOG_FILE" || true

log "After:  $(df -h / | awk 'NR==2 {print $3" used, "$4" free, "$5" full"}')"
log "=== Cleanup done ==="
