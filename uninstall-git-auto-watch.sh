#!/bin/bash

set -e

SERVICE_FILE="$HOME/.config/systemd/user/git-auto-watch.service"
BASE_DIR="$HOME/git-auto-watch"
INSTALLER_DIR="$HOME/git-auto-watch-installer"
LOCKFILE="/tmp/git-auto-watch.lock"

echo "🛑 Stoppe und deaktiviere systemd-Service..."
systemctl --user stop git-auto-watch.service || true
systemctl --user disable git-auto-watch.service || true

echo "🧹 Entferne Service-Datei..."
rm -f "$SERVICE_FILE"

echo "🧹 Entferne Watch-Verzeichnis..."
rm -rf "$BASE_DIR"

echo "🧹 Entferne Installer-Verzeichnis..."
rm -rf "$INSTALLER_DIR"

if [ -f "$LOCKFILE" ]; then
    echo "🔓 Entferne Lockfile..."
    rm -f "$LOCKFILE"
fi

systemctl --user daemon-reexec

echo "✅ Git Auto Watch und Installer wurden vollständig entfernt."
