#!/bin/bash

# === Konfiguration – nur hier anpassen ===
GIT_NAME="EntenPaule"
GIT_EMAIL="git@entenpaule.local"
GITHUB_USER="EntenPaule"

# === Allgemeine Einstellungen ===
BASE_DIR="$HOME/git-auto-watch"
REPO_DIR="$BASE_DIR/local-repo"
WATCH_DIRS=("$HOME/printer_data/config" "$HOME/printer_data/database")
SCRIPT_FILE="$BASE_DIR/git-auto-watch.sh"
ENV_FILE="$BASE_DIR/.env"
GITIGNORE_FILE="$BASE_DIR/.gitignore"
SERVICE_FILE="$HOME/.config/systemd/user/git-auto-watch.service"
LOG_FILE="$BASE_DIR/git-auto-watch.log"
BRANCH="main"

rm -rf "$BASE_DIR"
mkdir -p "$REPO_DIR"
mkdir -p "$(dirname "$SERVICE_FILE")"

# SSH-Key erzeugen, falls nicht vorhanden
if [ ! -f "$HOME/.ssh/id_ed25519" ]; then
    echo "🔐 Erstelle SSH-Key für GitHub..."
    ssh-keygen -t ed25519 -C "$GIT_EMAIL" -N "" -f "$HOME/.ssh/id_ed25519"
    echo ""
    echo "📋 Öffentlichen Schlüssel zu GitHub hinzufügen:"
    cat "$HOME/.ssh/id_ed25519.pub"
    echo "👉 https://github.com/settings/ssh/new"
    read -rsp $'\n🔑 Sobald der Schlüssel hinzugefügt ist, drücke [Enter] ...\n'
fi

# Git-User konfigurieren
git config --global user.name "$GIT_NAME"
git config --global user.email "$GIT_EMAIL"

# Pakete installieren
echo "📦 Installiere Pakete..."
sudo apt-get update -qq
sudo apt-get install -y git inotify-tools curl rsync

# Benutzerabfragen
DEFAULT_REPO="$(hostname)"
read -rp "📦 GitHub-Repo-Name [$DEFAULT_REPO]: " REPO_NAME
REPO_NAME=${REPO_NAME:-$DEFAULT_REPO}

read -rp "🔑 GitHub Token (wird nur lokal gespeichert): " GITHUB_TOKEN
echo ""

read -rp "🛠️  Soll 'updatemcu.sh' nach jedem Commit ausgeführt werden? (y/N): " USE_MCU
USE_MCU_UPDATE=false
[[ "$USE_MCU" =~ ^[Yy]$ ]] && USE_MCU_UPDATE=true

# .env erzeugen
cat > "$ENV_FILE" <<EOF
REPO_DIR="$REPO_DIR"
GITHUB_USER="$GITHUB_USER"
REPO_NAME="$REPO_NAME"
GITHUB_TOKEN="$GITHUB_TOKEN"
BRANCH="$BRANCH"
ENABLE_LOGGING=true
ENABLE_DEBUG=true
USE_MCU_UPDATE=$USE_MCU_UPDATE
LOG_FILE="$LOG_FILE"
WATCH_DIRS="${WATCH_DIRS[*]}"
EOF

chmod 600 "$ENV_FILE"

# Git-Repo initialisieren
cd "$REPO_DIR"
git init -b "$BRANCH"
touch .gitkeep
git add .
git commit -m "Initial commit"

# GitHub Repo erstellen
echo "🌀 Erstelle GitHub-Repo '$REPO_NAME'..."
response=$(curl -s -w "%{http_code}" -o /tmp/github_response.json \
    -H "Authorization: token $GITHUB_TOKEN" \
    https://api.github.com/user/repos \
    -d "{\"name\":\"$REPO_NAME\", \"private\":true}")

if [ "$response" = "201" ]; then
    echo "✅ Repo erfolgreich erstellt."
elif [ "$response" = "422" ]; then
    echo "ℹ️  Repo existiert vermutlich bereits."
else
    echo "❌ Fehler ($response):"
    cat /tmp/github_response.json
    exit 1
fi

git remote add origin "git@github.com:$GITHUB_USER/$REPO_NAME.git"
git push -u origin "$BRANCH" --force

# === Watcher-Skript ===
cat > "$SCRIPT_FILE" <<'EOF'
#!/bin/bash
source "$(dirname "$0")/.env"

log() {
    [ "$ENABLE_LOGGING" = true ] && echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}
debug() {
    [ "$ENABLE_DEBUG" = true ] && log "DEBUG: $*"
}

log "Starte Überwachung..."

while true; do
    inotifywait -r -e modify,create,delete,move $WATCH_DIRS > /dev/null 2>&1

    for dir in $WATCH_DIRS; do
        name=$(basename "$dir")
        target="$REPO_DIR/$name"
        mkdir -p "$target"

        rsync -a --delete --checksum "$dir/" "$target/"

        cd "$REPO_DIR" || continue
        git add -A

        if ! git diff --cached --quiet; then
            TIMESTAMP=$(date "+%Y-%m-%d %H:%M:%S")
            git commit -m "Auto-Update: $TIMESTAMP"
            git push origin "$BRANCH" > /dev/null 2>&1
            log "Änderung gepusht: $TIMESTAMP"

            if [ "$USE_MCU_UPDATE" = true ]; then
                MCU="$HOME/printer_data/config/script/updatemcu.sh"
                [ -x "$MCU" ] && "$MCU" && log "MCU-Skript ausgeführt"
            fi
        else
            debug "Keine Änderungen erkannt"
        fi
    done

done
EOF

chmod +x "$SCRIPT_FILE"

# systemd-Service erstellen
cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Git Auto Watcher
After=network-online.target

[Service]
ExecStart=$SCRIPT_FILE
Restart=always
Environment=ENV_FILE=$ENV_FILE

[Install]
WantedBy=default.target
EOF

# Service starten & Setup ausführen
systemctl --user daemon-reexec
systemctl --user enable --now git-auto-watch.service

"$SCRIPT_FILE" --setup

echo ""
echo "✅ Alles eingerichtet!"
echo "📦 Repo: $REPO_NAME"
echo "👤 User: $GIT_NAME <$GIT_EMAIL>"
echo "📁 Watch: ${WATCH_DIRS[*]}"
echo "🧪 MCU-Update: $USE_MCU_UPDATE"
