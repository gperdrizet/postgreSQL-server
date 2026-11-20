#!/bin/bash
# Load and validate the project .env for all admin scripts.
# Usage: . "$SCRIPT_DIR/lib/load-env.sh"   (from a script, not executed directly)

# Use prefixed names so we don't clobber the caller's SCRIPT_DIR / PROJECT_ROOT.
LOAD_ENV_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOAD_ENV_PROJECT_ROOT="$(cd "$LOAD_ENV_SCRIPT_DIR/../.." && pwd)"
ENV_FILE="${ENV_FILE:-$LOAD_ENV_PROJECT_ROOT/.env}"

if [[ ! -f "$ENV_FILE" ]]; then
    echo "Error: $ENV_FILE not found. Copy .env.template to .env and fill it in." >&2
    exit 1
fi

set -a
# shellcheck disable=SC1090
. "$ENV_FILE"
set +a

for setting in POSTGRES_ADMIN_PASSWORD PGADMIN_DEFAULT_PASSWORD PGADMIN_DEFAULT_EMAIL \
               TAILSCALE_IP DB_HOST DB_PORT DB_USER PGDATA_DIR BACKUP_DIR; do
    if [[ -z "${!setting:-}" ]]; then
        echo "Error: $setting is not set in $ENV_FILE." >&2
        echo "Copy .env.template to .env and fill in every value." >&2
        exit 1
    fi
done
