#!/bin/bash

# Configuration - UPDATE THIS PATH
BACKUP_DIR="/path/to/hdd-raid/postgres-backups"
DOCKER_CONTAINER="student-postgres"
RETENTION_DAYS=30
DATE=$(date +%Y-%m-%d_%H-%M-%S)

# Create backup directory
mkdir -p "$BACKUP_DIR"

echo "=========================================="
echo "PostgreSQL Backup"
echo "Started at: $(date)"
echo "=========================================="

# Dump all databases
echo "Dumping all databases..."
docker exec $DOCKER_CONTAINER pg_dumpall -U admin | gzip > "$BACKUP_DIR/full_backup_$DATE.sql.gz"

if [ $? -eq 0 ]; then
    SIZE=$(du -h "$BACKUP_DIR/full_backup_$DATE.sql.gz" | cut -f1)
    echo "✓ Backup completed successfully"
    echo "  File: $BACKUP_DIR/full_backup_$DATE.sql.gz"
    echo "  Size: $SIZE"
else
    echo "✗ Backup failed!"
    exit 1
fi

# Clean up old backups
echo ""
echo "Cleaning up backups older than $RETENTION_DAYS days..."
DELETED=$(find "$BACKUP_DIR" -name "full_backup_*.sql.gz" -mtime +$RETENTION_DAYS -delete -print | wc -l)
echo "Deleted $DELETED old backup(s)"

echo ""
echo "=========================================="
echo "Backup completed at: $(date)"
echo "=========================================="
