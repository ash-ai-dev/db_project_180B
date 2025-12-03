#!/usr/bin/env bash
# Usage:
#   ./scripts/backup_pg.sh /path/to/backup.sql
#   ./scripts/backup_pg.sh            # writes to backups/<db>-YYYYmmdd-HHMMSS.sql
#
# Description:
#   Create a SQL dump of a PostgreSQL database using pg_dump.
#   The script writes a plain SQL file that can be restored with psql.
#
# Environment variables (defaults shown):
#   PG_HOST       ${PG_HOST:-localhost}
#   PG_PORT       ${PG_PORT:-5432}
#   PG_NAME       ${PG_NAME:-smart_campus}
#   PG_USER       ${PG_USER:-postgres}
#   PG_PASSWORD   ${PG_PASSWORD:-}     # if set, PGPASSWORD is used for authentication
#   BACKUP_DIR    ${BACKUP_DIR:-backups}
#   PG_DUMP_OPTS  ${PG_DUMP_OPTS:-}    # extra flags to pass to pg_dump, e.g. --format=custom
#
# Examples:
#   PG_PASSWORD=secret ./scripts/backup_pg.sh backups/smart_campus.sql
#   ./scripts/backup_pg.sh  # creates a timestamped file in backups/
#
# Notes:
#   - Ensure pg_dump is installed and available in PATH.
#   - Backups may contain sensitive data; store them securely and do not commit to VCS.
#   - Running without sufficient DB privileges will cause pg_dump to fail.

if [ -z "$1" ]; then
  echo "Usage: $0 /path/to/backup.sql"
  exit 1
fi

BACKUP_FILE="$1"

if [ ! -f "${BACKUP_FILE}" ]; then
  echo "Backup file not found: ${BACKUP_FILE}"
  exit 1
fi

PG_HOST="${PG_HOST:-localhost}"
PG_PORT="${PG_PORT:-5432}"
PG_NAME="${PG_NAME:-smart_campus}"
PG_USER="${PG_USER:-postgres}"
PG_PASSWORD="${PG_PASSWORD:-}"

echo "You are about to restore database '${PG_NAME}' from:"
echo "  ${BACKUP_FILE}"
echo "This will DROP AND RECREATE the database."
read -p "Type YES to continue: " CONFIRM

if [ "${CONFIRM}" != "YES" ]; then
  echo "Restore cancelled."
  exit 0
fi

echo "Dropping and recreating '${PG_NAME}'..."

if [ -n "${PG_PASSWORD}" ]; then
  PGPASSWORD="${PG_PASSWORD}" psql \
    --host="${PG_HOST}" \
    --port="${PG_PORT}" \
    --username="${PG_USER}" \
    -c "DROP DATABASE IF EXISTS ${PG_NAME}; CREATE DATABASE ${PG_NAME};"
else
  psql \
    --host="${PG_HOST}" \
    --port="${PG_PORT}" \
    --username="${PG_USER}" \
    -c "DROP DATABASE IF EXISTS ${PG_NAME}; CREATE DATABASE ${PG_NAME};"
fi

echo "Restoring backup..."

if [ -n "${PG_PASSWORD}" ]; then
  PGPASSWORD="${PG_PASSWORD}" psql \
    --host="${PG_HOST}" \
    --port="${PG_PORT}" \
    --username="${PG_USER}" \
    --dbname="${PG_NAME}" \
    -f "${BACKUP_FILE}"
else
  psql \
    --host="${PG_HOST}" \
    --port="${PG_PORT}" \
    --username="${PG_USER}" \
    --dbname="${PG_NAME}" \
    -f "${BACKUP_FILE}"
fi

if [ $? -eq 0 ]; then
  echo "Restore complete."
else
  echo "Restore failed."
  exit 1
fi
