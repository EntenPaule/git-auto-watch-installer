#!/bin/bash

set -e

SERVICE_FILE="$HOME/.config/systemd/user/git-auto-watch.service"
BASE_DIR="$HOME/git-auto-watch"

echo "🛑 Stoppe und entferne systemd-Service..."
systemctl --user stop git-auto-watch.service || true
systemctl --user disable git-auto-watch.service || true
rm -f "$SERVICE_FILE"

echo "🧹 Entferne lokale Dateien unter $BASE_DIR..."
rm -rf "$BASE_DIR"

echo "🔁 systemd neu laden..."
systemctl --user daemon-reexec

echo "✅ Deinstallation abgeschlossen."
