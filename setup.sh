#!/bin/bash

# === Konfiguration ===
GIT_NAME="EntenPaule"
GIT_EMAIL="git@entenpaule.local"
GITHUB_USER="EntenPaule"
REPO_NAME="$(hostname)"
BRANCH="main"

BASE_DIR="$HOME/git-auto-watch"
REPO_DIR="$BASE_DIR/local-repo"
WATCH_DIRS=("$HOME/printer_data/config" "$HOME/printer_data/database")

SCRIPT_FILE="$BASE_DIR/git-auto-watch.sh"
ENV_FILE="$BASE_DIR/.env"
SERVICE_FILE="$HOME/.config/systemd/user/git-auto-watch.service"
LOG_FILE="$BASE_DIR/git-auto-watch.log"

rm -rf "$BASE_DIR"
mkdir -p "$REPO_DIR"
mkdir -p "$(dirname "$SERVICE_FILE")"

# SSH-Key erzeugen
if [ ! -f "$HOME/.ssh/id_ed25519" ]; then
    echo "🔐 Erstelle SSH-Key für GitHub..."
    ssh-keygen -t ed25519 -C "$GIT_EMAIL" -N "" -f "$HOME/.ssh/id_ed25519"
    echo ""
    echo "📋 Füge diesen Schlüssel zu GitHub hinzu:"
    cat "$HOME/.ssh/id_ed25519.pub"
    echo "👉 https://github.com/settings/ssh/new"
    read -rsp $'\n🔑 Wenn fertig, [Enter] drücken ...\n'
fi

# Git global setzen
git config --global user.name "$GIT_NAME"
git config --global user.email "$GIT_EMAIL"

# Pakete installieren
echo "📦 Installiere Pakete..."
sudo apt-get update -qq
sudo apt-get install -y git inotify-tools curl rsync

# Token & MCU abfragen
read -rsp "🔑 GitHub Token (nur lokal): " GITHUB_TOKEN
echo ""
read -rp "🛠️  Soll 'updatemcu.sh' nach jedem Commit ausgeführt werden? (y/N): " USE_MCU
USE_MCU_UPDATE=false
[[ "$USE_MCU" =~ ^[Yy]$ ]] && USE_MCU_UPDATE=true

# .env
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
        dest="$REPO_DIR/$name"
        mkdir -p "$dest"
        rsync -a --delete "$dir/" "$dest/"

        cd "$REPO_DIR" || continue
        git add .
        TIMESTAMP=$(date "+%Y-%m-%d %H:%M:%S")
        git commit -m "Auto-Update: $TIMESTAMP" > /dev/null 2>&1
        if [ $? -eq 0 ]; then
            git push origin "$BRANCH" > /dev/null 2>&1
            log "Änderung gepusht: $TIMESTAMP"
            if [ "$USE_MCU_UPDATE" = true ]; then
                MCU="$HOME/printer_data/config/script/updatemcu.sh"
                [ -x "$MCU" ] && "$MCU" && log "MCU-Skript ausgeführt"
            fi
        else
            debug "Keine Änderungen."
        fi
    done
done
EOF

chmod +x "$SCRIPT_FILE"

# === systemd-Service ===
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

systemctl --user daemon-reexec
systemctl --user enable --now git-auto-watch.service

echo ""
echo "✅ Alles eingerichtet!"
echo "📦 Git-Repo: $REPO_NAME"
echo "📁 Lokales Repo: $REPO_DIR"
echo "👀 Beobachtet: ${WATCH_DIRS[*]}"
echo "🧪 MCU-Update: $USE_MCU_UPDATE"
