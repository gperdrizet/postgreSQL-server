#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT_PATH="$SCRIPT_DIR/backup.sh"
LOG_FILE="/var/log/postgres-backup.log"

# Verify backup script exists
if [ ! -f "$SCRIPT_PATH" ]; then
    echo "Error: backup.sh not found at $SCRIPT_PATH"
    exit 1
fi

# Make sure backup script is executable
chmod +x "$SCRIPT_PATH"

# Create cron job (daily at 3 AM)
CRON_JOB="0 3 * * * $SCRIPT_PATH >> $LOG_FILE 2>&1"

# Add cron job (avoiding duplicates)
(crontab -l 2>/dev/null | grep -v "$SCRIPT_PATH"; echo "$CRON_JOB") | crontab -

echo "✓ Backup cron job installed"
echo "  Schedule: Daily at 3:00 AM"
echo "  Script: $SCRIPT_PATH"
echo "  Log: $LOG_FILE"
echo ""
echo "To view current cron jobs: crontab -l"
echo "To remove: crontab -e (and delete the line)"
