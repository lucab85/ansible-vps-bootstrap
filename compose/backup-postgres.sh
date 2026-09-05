#!/bin/bash
set -euo pipefail

BACKUP_DIR="/opt/apps/backups"
RETENTION_DAYS=30
CONTAINER="apps-postgres-1"
LOG_FILE="$BACKUP_DIR/backup.log"
METRICS_FILE="/opt/apps/monitoring/textfile_collector/postgres_backup.prom"

set -a
. /opt/apps/.env
set +a

TIMESTAMP=$(date +%Y%m%d_%H%M%S)

log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >> "$LOG_FILE"
}

log "Starting backup"

DATABASES=$(docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" "$CONTAINER" \
  psql -U "$POSTGRES_USER" -d postgres -tAc \
  "SELECT datname FROM pg_database WHERE datistemplate = false;")

declare -A LAST_SUCCESS
if [[ -f "$METRICS_FILE" ]]; then
  while read -r line; do
    if [[ "$line" =~ ^pg_backup_last_success_timestamp_seconds\{database=\"([^\"]+)\"\}\ ([0-9]+)$ ]]; then
      LAST_SUCCESS["${BASH_REMATCH[1]}"]="${BASH_REMATCH[2]}"
    fi
  done < "$METRICS_FILE"
fi

declare -A RUN_STATUS
for db in $DATABASES; do
  DEST="$BACKUP_DIR/${db}_${TIMESTAMP}.dump"
  if docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" "$CONTAINER" \
      pg_dump -U "$POSTGRES_USER" -Fc -d "$db" > "$DEST"; then
    log "OK  $db -> $DEST"
    LAST_SUCCESS["$db"]=$(date +%s)
    RUN_STATUS["$db"]=1
  else
    log "FAIL $db"
    rm -f "$DEST"
    RUN_STATUS["$db"]=0
  fi
done

find "$BACKUP_DIR" -maxdepth 1 -name "*.dump" -mtime "+${RETENTION_DAYS}" -delete
log "Rotation complete (retention ${RETENTION_DAYS}d)"

METRICS_TMP="${METRICS_FILE}.tmp"
mkdir -p "$(dirname "$METRICS_FILE")"
{
  echo "# HELP pg_backup_last_success_timestamp_seconds Unix time of the last successful pg_dump per database"
  echo "# TYPE pg_backup_last_success_timestamp_seconds gauge"
  for db in "${!LAST_SUCCESS[@]}"; do
    echo "pg_backup_last_success_timestamp_seconds{database=\"$db\"} ${LAST_SUCCESS[$db]}"
  done
  echo "# HELP pg_backup_last_run_status 1 if the most recent backup attempt for this database succeeded, 0 otherwise"
  echo "# TYPE pg_backup_last_run_status gauge"
  for db in "${!RUN_STATUS[@]}"; do
    echo "pg_backup_last_run_status{database=\"$db\"} ${RUN_STATUS[$db]}"
  done
} > "$METRICS_TMP"
mv "$METRICS_TMP" "$METRICS_FILE"
