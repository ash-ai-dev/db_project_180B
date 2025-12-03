#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# PostgreSQL backup script
#
# PostgreSQL connection settings
# PG_HOST        default: localhost
# PG_PORT        default: 5432
# PG_NAME        default: smart_campus    # set your real DB name
# PG_USER        default: postgres
# PG_PASSWORD    default: empty
#
# Backup settings
# BACKUP_DIR     default: ./backups
# TIMESTAMP      generated via date +"%Y%m%d_%H%M%S"
# BACKUP_FILE    composed as ${BACKUP_DIR}/${PG_NAME}_${TIMESTAMP}.sql
#
# Uses PGPASSWORD env var so the command doesn’t prompt.
# -----------------------------------------------------------------------------

PG_HOST="${PG_HOST:-localhost}"
PG_PORT="${PG_PORT:-5432}"
PG_NAME="${PG_NAME:-smart_campus}"
PG_USER="${PG_USER:-postgres}"
PG_PASSWORD="${PG_PASSWORD:-}"

BACKUP_DIR="${BACKUP_DIR:-./backups}"
TIMESTAMP="$(date +"%Y%m%d_%H%M%S")"
BACKUP_FILE="${BACKUP_DIR}/${PG_NAME}_${TIMESTAMP}.sql"

mkdir -p "${BACKUP_DIR}"

echo "Backing up PostgreSQL database '${PG_NAME}'"
echo "Backup directory: ${BACKUP_DIR}"

if [ -n "${PG_PASSWORD}" ]; then
  PGPASSWORD="${PG_PASSWORD}" pg_dump \
    --host="${PG_HOST}" \
    --port="${PG_PORT}" \
    --username="${PG_USER}" \
    --format=plain \
    --no-owner \
    --no-privileges \
    "${PG_NAME}" > "${BACKUP_FILE}"
else
  pg_dump \
    --host="${PG_HOST}" \
    --port="${PG_PORT}" \
    --username="${PG_USER}" \
    --format=plain \
    --no-owner \
    --no-privileges \
    "${PG_NAME}" > "${BACKUP_FILE}"
fi

if [ $? -eq 0 ]; then
  echo "Backup completed: ${BACKUP_FILE}"
else
  echo "Backup failed"
  exit 1
fi
