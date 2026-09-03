#!/bin/bash
set -e

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
    CREATE USER postgres_exporter WITH PASSWORD '${POSTGRES_EXPORTER_PASSWORD}';
    GRANT pg_monitor TO postgres_exporter;
EOSQL
