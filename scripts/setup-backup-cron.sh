#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/load-env.sh
. "$SCRIPT_DIR/lib/load-env.sh"

SCRIPT_PATH="$SCRIPT_DIR/backup.sh"
LOG_FILE="$BACKUP_DIR/backup.log"

# Verify backup script exists
if [ ! -f "$SCRIPT_PATH" ]; then
    echo "Error: backup.sh not found at $SCRIPT_PATH"
    exit 1
fi

# The log lives with the backups so an unprivileged cron user can write it
mkdir -p "$BACKUP_DIR"
if [ ! -w "$BACKUP_DIR" ]; then
    echo "Error: $BACKUP_DIR is not writable by $(id -un)."
    echo "Fix its ownership before installing the cron job."
    exit 1
fi

# Make sure backup script is executable
chmod +x "$SCRIPT_PATH"

# Create cron job (daily at 3 AM). Set PATH explicitly: cron has a minimal environment.
CRON_JOB="0 3 * * * PATH=/usr/local/bin:/usr/bin:/bin $SCRIPT_PATH >> $LOG_FILE 2>&1"

# Replace any existing backup entry (regardless of checkout path) to avoid duplicates
(crontab -l 2>/dev/null | grep -v 'backup\.sh' || true; echo "$CRON_JOB") | crontab -

echo "✓ Backup cron job installed"
echo "  Schedule: Daily at 3:00 AM"
echo "  Script: $SCRIPT_PATH"
echo "  Log: $LOG_FILE"
echo ""
echo "To view current cron jobs: crontab -l"
echo "To remove: crontab -e (and delete the line)"
