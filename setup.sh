#!/bin/bash

# === Farben ===
GRN='\033[0;32m'
RED='\033[0;31m'
YLW='\033[1;33m'
BLU='\033[1;34m'
NC='\033[0m' # kein Farbcode

# === Konfiguration – nur hier anpassen ===
GIT_NAME="EntenPaule"
GIT_EMAIL="git@entenpaule.local"
GITHUB_USER="EntenPaule"

# === Allgemeine Einstellungen ===

# Wenn .env existiert, Werte laden und Setup überspringen
if [ -f "$HOME/git-auto-watch/.env" ]; then
    echo -e "
${GRN}⚙️  Vorhandene Konfiguration gefunden – .env wird verwendet.${NC}"
    source "$HOME/git-auto-watch/.env"
    echo -e "${YLW}⏩ Setup wird übersprungen.${NC}"
    exit 0
fi

BASE_DIR="$HOME/git-auto-watch"
REPO_DIR="$BASE_DIR/local-repo"
WATCH_DIRS=("$HOME/printer_data/config" "$HOME/printer_data/database")
SCRIPT_FILE="$BASE_DIR/git-auto-watch.sh"
ENV_FILE="$BASE_DIR/.env"
SERVICE_FILE="$HOME/.config/systemd/user/klipper-conf-git.service"
LOG_FILE="$BASE_DIR/git-auto-watch.log"
BRANCH="main"

rm -rf "$BASE_DIR"
mkdir -p "$REPO_DIR"
mkdir -p "$(dirname "$SERVICE_FILE")"

# SSH-Key erzeugen, falls nicht vorhanden
if [ ! -f "$HOME/.ssh/id_ed25519" ]; then
    echo -e "${YLW}🔐 Erstelle SSH-Key für GitHub...${NC}"
    ssh-keygen -t ed25519 -C "$GIT_EMAIL" -N "" -f "$HOME/.ssh/id_ed25519"
    echo ""
    echo -e "${BLU}📋 Öffentlichen Schlüssel zu GitHub hinzufügen:${NC}"
    cat "$HOME/.ssh/id_ed25519.pub"
    echo -e "${BLU}👉 https://github.com/settings/ssh/new${NC}"
    read -rsp $'\n🔑 Sobald der Schlüssel hinzugefügt ist, drücke [Enter] ...\n'
fi

# Git-User konfigurieren
git config --global user.name "$GIT_NAME"
git config --global user.email "$GIT_EMAIL"

# Pakete installieren
echo -e "${YLW}📦 Installiere Pakete...${NC}"
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

# Prüfen auf eingebettete Repos und ggf. löschen
for dir in "${WATCH_DIRS[@]}"; do
    if [ -d "$dir/.git" ]; then
        echo -e "${RED}⚠️  Warnung: '$dir' ist ein Git-Repository.${NC}"
        read -rp "❌ Soll .git in '$dir' entfernt werden? (y/N): " rm_git
        if [[ "$rm_git" =~ ^[Yy]$ ]]; then
            rm -rf "$dir/.git"
            echo -e "${YLW}📁 Entfernt: $dir/.git${NC}"
        else
            echo -e "${RED}⛔ Abbruch – eingebettetes Repo vorhanden.${NC}"
            exit 1
        fi
    fi
done

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

# Erstes Synchronisieren aller WATCH_DIRS
echo -e "${YLW}📁 Synchronisiere initiale Dateien...${NC}"
for dir in "${WATCH_DIRS[@]}"; do
    name=$(basename "$dir")
    target="$REPO_DIR/$name"
    mkdir -p "$target"
    rsync -a --delete --checksum "$dir/" "$target/"
done

git add -A
git commit -m "Initial commit from setup"

# GitHub Repo erstellen
echo -e "${YLW}🌀 Erstelle GitHub-Repo '$REPO_NAME'...${NC}"
response=$(curl -s -w "%{http_code}" -o /tmp/github_response.json \
    -H "Authorization: token $GITHUB_TOKEN" \
    https://api.github.com/user/repos \
    -d "{\"name\":\"$REPO_NAME\", \"private\":true}")

if [ "$response" = "201" ]; then
    echo -e "${GRN}✅ Repo erfolgreich erstellt.${NC}"
elif [ "$response" = "422" ]; then
    echo -e "${YLW}ℹ️  Repo existiert vermutlich bereits.${NC}"
else
    echo -e "${RED}❌ Fehler ($response):${NC}"
    cat /tmp/github_response.json
    exit 1
fi

git remote add origin "git@github.com:$GITHUB_USER/$REPO_NAME.git"
git push -u origin "$BRANCH" --force

# git-auto-watch.sh erzeugen
cat > "$SCRIPT_FILE" <<'EOF'
#!/bin/bash

source "$(dirname "$0")/.env"

log() {
    [ "$ENABLE_LOGGING" = true ] && echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}
debug() {
    [ "$ENABLE_DEBUG" = true ] && log "DEBUG: $*"
}

LOCKFILE="/tmp/git-auto-watch.lock"
log "Starte Überwachung..."

while true; do
    inotifywait -r -e modify,create,delete,move $WATCH_DIRS > /dev/null 2>&1

    ( flock -n 9 || exit 1

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
    ) 9>"$LOCKFILE"
done
EOF

chmod +x "$SCRIPT_FILE"

# systemd-Service erstellen
SERVICE_FILE="$HOME/.config/systemd/user/klipper-conf-git.service"
mkdir -p "$(dirname "$SERVICE_FILE")"
cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Git Auto Watcher für Klipper-Config
After=network-online.target

[Service]
Type=simple
ExecStart=$SCRIPT_FILE
Restart=always
Environment=ENV_FILE=$ENV_FILE

[Install]
WantedBy=default.target
EOF

systemctl --user daemon-reexec
systemctl --user enable --now klipper-conf-git.service


# Selbsttest
sleep 1
STATUS=$(systemctl --user is-active klipper-conf-git.service)
if [ "$STATUS" = "active" ]; then
    echo -e "
${GRN}🟢 Dienst läuft einwandfrei.${NC}"
else
    echo -e "
${RED}🔴 Dienst konnte nicht gestartet werden.${NC}"
    journalctl --user -u klipper-conf-git.service --no-pager -n 10
fi

# Update-Manager-Eintrag direkt in moonraker.conf schreiben
MOON_CFG="$HOME/printer_data/config/moonraker.conf"
INSTALLER_NAME="git-auto-watch-installer"

if grep -q "^\[update_manager $INSTALLER_NAME\]" "$MOON_CFG" 2>/dev/null; then
    echo -e "${YLW}ℹ️  Update Manager-Eintrag für '$INSTALLER_NAME' existiert bereits in moonraker.conf.${NC}"
else
    echo -e "${YLW}➕ Trage '$INSTALLER_NAME' in moonraker.conf ein...${NC}"
    cat >> "$MOON_CFG" <<EOF

[update_manager $INSTALLER_NAME]
type: git_repo
path: $HOME/git-auto-watch-installer
origin: https://github.com/$GITHUB_USER/git-auto-watch-installer.git
EOF
    echo -e "${GRN}✅ Update Manager-Eintrag hinzugefügt.${NC}"

    echo -e "${YLW}🔁 Starte Moonraker neu, damit der Eintrag aktiv wird...${NC}"
    sudo systemctl restart moonraker.service
    echo -e "${GRN}✅ Moonraker wurde neu gestartet.${NC}"
fi
fi
fi

# Ergebnis anzeigen
echo -e "

${GRN}✅ Alles eingerichtet und gestartet!${NC}
"
echo -e "📦 Repo:        ${BLU}$REPO_NAME${NC}"
echo -e "👤 User:        ${BLU}$GIT_NAME <$GIT_EMAIL>${NC}"
echo -e "📁 Watch:       ${BLU}${WATCH_DIRS[*]}${NC}"
echo -e "🧪 MCU-Update:  ${BLU}$USE_MCU_UPDATE${NC}"
echo -e "📝 Logfile:     ${BLU}$LOG_FILE${NC}"
echo -e "📂 Repo-Ordner: ${BLU}$REPO_DIR${NC}"

echo -e "
🔍 Prüfe Status mit:
  ${YLW}tail -f $LOG_FILE${NC}"
echo -e "
⏎ ${BLU}Drücke [Enter] zum Beenden des Setups ...${NC}"
cd ~
read -r dummy_input
