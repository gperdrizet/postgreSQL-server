#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SERVICE_NAME="postgresql-server-stack.service"
OLD_SERVICE_NAME="fullstack-sql-stack.service"
SERVICE_PATH="/etc/systemd/system/$SERVICE_NAME"

if ! command -v docker >/dev/null 2>&1; then
    echo "Error: docker is not installed"
    exit 1
fi

if ! docker compose version >/dev/null 2>&1; then
    echo "Error: docker compose plugin is not available"
    exit 1
fi

if [[ "${1:-}" == "--uninstall" ]]; then
    echo "Removing startup service..."
    sudo systemctl disable "$SERVICE_NAME" >/dev/null 2>&1 || true
    sudo rm -f "$SERVICE_PATH"
    sudo systemctl disable "$OLD_SERVICE_NAME" >/dev/null 2>&1 || true
    sudo rm -f "/etc/systemd/system/$OLD_SERVICE_NAME"
    sudo systemctl daemon-reload
    echo "✓ Removed $SERVICE_NAME"
    exit 0
fi

echo "Installing startup service for project at: $PROJECT_ROOT"

# Cleanup old service name if it exists.
sudo systemctl disable "$OLD_SERVICE_NAME" >/dev/null 2>&1 || true
sudo rm -f "/etc/systemd/system/$OLD_SERVICE_NAME"

sudo tee "$SERVICE_PATH" >/dev/null <<EOF
[Unit]
Description=PostgreSQL-server Docker Compose Stack
Requires=docker.service
After=docker.service network-online.target
Wants=network-online.target

[Service]
Type=oneshot
WorkingDirectory=$PROJECT_ROOT
ExecStart=/usr/bin/docker compose up -d
ExecStop=/usr/bin/docker compose down
RemainAfterExit=yes
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable "$SERVICE_NAME"
sudo systemctl start "$SERVICE_NAME"

echo "✓ Installed and started $SERVICE_NAME"
echo "  Service file: $SERVICE_PATH"
echo ""
echo "Check status with: sudo systemctl status $SERVICE_NAME"
