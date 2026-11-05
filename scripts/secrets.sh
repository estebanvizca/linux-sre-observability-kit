#!/usr/bin/env bash
#
# Generate the lab's local secrets exactly once.
#
# Nothing generated here is committed: everything lives under .cache/secrets,
# which is ignored by Git. Re-running the script keeps the existing values so
# that the restic repository and its credentials stay in sync.
#
#   RESTIC_PASSWORD      encryption password for the restic repository
#   RESTIC_REST_PASSWORD  HTTP basic-auth password for the rest-server
#   rest-server.htpasswd  bcrypt hash consumed by rest-server
#
set -euo pipefail
umask 077

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SECRETS="${ROOT}/.cache/secrets"
RESTIC_PASSWORD_FILE="${SECRETS}/restic-password"
REST_PASSWORD_FILE="${SECRETS}/rest-server-password"
HTPASSWD_FILE="${SECRETS}/rest-server.htpasswd"

log() { printf '[secrets] %s\n' "$*" >&2; }
have() { command -v "$1" >/dev/null 2>&1; }

mkdir -p "${SECRETS}"
chmod 700 "${SECRETS}"

if [ ! -s "${RESTIC_PASSWORD_FILE}" ]; then
  have openssl || { echo "openssl is required" >&2; exit 1; }
  openssl rand -hex 24 > "${RESTIC_PASSWORD_FILE}"
  chmod 600 "${RESTIC_PASSWORD_FILE}"
  log "generated restic repository password"
fi

if [ ! -s "${REST_PASSWORD_FILE}" ]; then
  have openssl || { echo "openssl is required" >&2; exit 1; }
  openssl rand -hex 24 > "${REST_PASSWORD_FILE}"
  chmod 600 "${REST_PASSWORD_FILE}"
  log "generated rest-server basic-auth password"
fi

if [ ! -s "${HTPASSWD_FILE}" ]; then
  have docker || { echo "docker is required to hash the rest-server password" >&2; exit 1; }
  # Bcrypt hashing with the same Apache tool rest-server expects. The password
  # is passed through an environment variable, never on the command line.
  REST_PASSWORD="$(cat "${REST_PASSWORD_FILE}")" \
    docker run --rm -e REST_PASSWORD httpd:2.4-alpine \
    sh -c 'htpasswd -nbB sre "$REST_PASSWORD"' > "${HTPASSWD_FILE}"
  chmod 600 "${HTPASSWD_FILE}"
  log "generated rest-server htpasswd file"
fi

log "secrets ready in ${SECRETS}"

if [ ! -s "${SECRETS}/grafana-password" ]; then
  openssl rand -hex 24 > "${SECRETS}/grafana-password"
fi
# Grafana runs as UID 472; the containing host directory stays mode 0700.
chmod 644 "${SECRETS}/grafana-password"
