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
FORCE=false
if [[ "$1" == "--force" ]]; then
    FORCE=true
fi

# Benutzerverzeichnis korrekt ermitteln, auch unter sudo
REAL_USER=$(logname)
REAL_USER_HOME=$(eval echo ~$REAL_USER)

BASE_DIR="$REAL_USER_HOME/git-auto-watch"
ENV_FILE="$BASE_DIR/.env"

if [ -f "$ENV_FILE" ] && [ "$FORCE" = false ]; then
    echo -e "\n${GRN}⚙️  Vorhandene Konfiguration gefunden – .env wird verwendet.${NC}"
    source "$ENV_FILE"
    echo -e "${YLW}⏩ Setup wird übersprungen.${NC}"
    exit 0
fi

REPO_DIR="$BASE_DIR/local-repo"
WATCH_DIRS=("$REAL_USER_HOME/printer_data/config" "$REAL_USER_HOME/printer_data/database")
SCRIPT_FILE="/usr/local/bin/git-auto-watch.sh"
SERVICE_FILE=""
LOG_FILE="$BASE_DIR/git-auto-watch.log"
BRANCH="master"

USE_SYSTEM=false
if [ "$FORCE" = false ]; then
    read -rp "🤩 Soll der Dienst systemweit laufen? (y/N): " USE_SYSTEM_INPUT
    if [[ "$USE_SYSTEM_INPUT" =~ ^[Yy]$ ]]; then
        USE_SYSTEM=true
    fi
fi

if [[ "$USE_SYSTEM" = true ]]; then
    SERVICE_FILE="/etc/systemd/system/klipper-conf-git.service"
    SYSTEM_WIDE=true
else
    SERVICE_FILE="$REAL_USER_HOME/.config/systemd/user/klipper-conf-git.service"
    SYSTEM_WIDE=false
fi

rm -rf "$BASE_DIR"
mkdir -p "$REPO_DIR"
mkdir -p "$(dirname "$SERVICE_FILE")"

# SSH-Key erzeugen, falls nicht vorhanden
if [ ! -f "$REAL_USER_HOME/.ssh/id_ed25519" ]; then
    echo -e "${YLW}🔐 Erstelle SSH-Key für GitHub...${NC}"
    sudo -u "$REAL_USER" ssh-keygen -t ed25519 -C "$GIT_EMAIL" -N "" -f "$REAL_USER_HOME/.ssh/id_ed25519"
    echo ""
    echo -e "${BLU}📋 Öffentlichen Schlüssel zu GitHub hinzufügen:${NC}"
    cat "$REAL_USER_HOME/.ssh/id_ed25519.pub"
    echo -e "${BLU}🔙 https://github.com/settings/ssh/new${NC}"
    read -rsp $'\n🔑 Sobald der Schlüssel hinzugefügt ist, drücke [Enter] ...\n'
fi

# Git-User konfigurieren
sudo -u "$REAL_USER" git config --global user.name "$GIT_NAME"
sudo -u "$REAL_USER" git config --global user.email "$GIT_EMAIL"

# Pakete installieren
function install_if_missing() {
    for pkg in "$@"; do
        if ! dpkg -s "$pkg" >/dev/null 2>&1; then
            echo -e "${YLW}📦 Installiere fehlendes Paket: $pkg${NC}"
            sudo apt-get install -y "$pkg"
        else
            echo -e "${GRN}✅ $pkg ist bereits installiert.${NC}"
        fi
    done
}

echo -e "${YLW}📦 Überprüfe erforderliche Pakete...${NC}"
sudo apt-get update -qq
install_if_missing git inotify-tools curl rsync

# Benutzerabfragen
DEFAULT_REPO="$(hostname)"
read -rp "📦 GitHub-Repo-Name [${DEFAULT_REPO}]: " REPO_NAME
REPO_NAME=${REPO_NAME:-$DEFAULT_REPO}

read -rp "🔑 GitHub Token (wird nur lokal gespeichert): " GITHUB_TOKEN
echo ""

read -rp "🛠️  Soll 'updatemcu.sh' nach jedem Commit ausgeführt werden? (y/N): " USE_MCU
USE_MCU_UPDATE=false
if [[ "$USE_MCU" =~ ^[Yy]$ ]]; then
    USE_MCU_UPDATE=true
fi

# Sicherstellen, dass Konfig-Verzeichnis vorhanden ist
for dir in "${WATCH_DIRS[@]}"; do
    if [ ! -d "$dir" ]; then
        echo -e "${RED}❌ Verzeichnis nicht gefunden: $dir${NC}"
        echo -e "${RED}Bitte sicherstellen, dass alle überwachten Verzeichnisse vorhanden sind.${NC}"
        echo -e "${YLW}📁 Erstelle Verzeichnis: $dir${NC}"
        mkdir -p "$dir"
    fi
    
    if [ ! -f "$dir/.gitkeep" ]; then
        touch "$dir/.gitkeep"
    fi

done

# .env erzeugen
cat > "$ENV_FILE" <<EOF
WATCH_DIRS="${WATCH_DIRS[*]}"
GITHUB_USER="$GITHUB_USER"
REPO_NAME="$REPO_NAME"
GITHUB_TOKEN="$GITHUB_TOKEN"
BRANCH="$BRANCH"
ENABLE_LOGGING=true
ENABLE_DEBUG=true
USE_MCU_UPDATE=$USE_MCU_UPDATE
LOG_FILE="$LOG_FILE"
EOF

chmod 600 "$ENV_FILE"

echo -e "${GRN}✅ .env-Datei erstellt unter $ENV_FILE${NC}"

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
sudo tee "$SCRIPT_FILE" > /dev/null <<'EOF'
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

sudo chmod +x "$SCRIPT_FILE"

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

if [ "$SYSTEM_WIDE" = true ]; then
    sudo systemctl daemon-reexec
    sudo systemctl enable --now klipper-conf-git.service
else
    systemctl --user daemon-reexec
    systemctl --user enable --now klipper-conf-git.service
fi


# Selbsttest
sleep 1
if [ "$SYSTEM_WIDE" = true ]; then
    STATUS=$(sudo systemctl is-active klipper-conf-git.service)
else
    STATUS=$(systemctl --user is-active klipper-conf-git.service)
fi
if [ "$STATUS" = "active" ]; then
    echo -e "
${GRN}🟢 Dienst läuft einwandfrei.${NC}"
else
    echo -e "
${RED}🔴 Dienst konnte nicht gestartet werden.${NC}"
    if [ "$SYSTEM_WIDE" = true ]; then
    sudo journalctl -u klipper-conf-git.service --no-pager -n 10
else
    journalctl --user -u klipper-conf-git.service --no-pager -n 10
fi
fi

# Update-Manager-Eintrag direkt in moonraker.conf schreiben
MOON_CFG="$HOME/printer_data/config/moonraker.conf"
INSTALLER_NAME="klipper-conf-git"

if grep -q "^\[update_manager $INSTALLER_NAME\]" "$MOON_CFG" 2>/dev/null; then
    echo -e "${YLW}ℹ️  Update Manager-Eintrag für '$INSTALLER_NAME' existiert bereits in moonraker.conf.${NC}"
else
    echo -e "${YLW}➕ Trage '$INSTALLER_NAME' in moonraker.conf ein...${NC}"
    cat >> "$MOON_CFG" <<EOF

[update_manager $INSTALLER_NAME]
primary_branch: master
type: git_repo
path: $HOME/git-auto-watch-installer
origin: https://github.com/$GITHUB_USER/klipper-conf-git.git
EOF
    echo -e "${GRN}✅ Update Manager-Eintrag hinzugefügt.${NC}"

    echo -e "${YLW}🔁 Starte Moonraker neu, damit der Eintrag aktiv wird...${NC}"
    sudo systemctl restart moonraker.service
    echo -e "${GRN}✅ Moonraker wurde neu gestartet.${NC}"
fi
fi
fi

# moonraker.asvc Eintrag für Service-Verwaltung
ASVC_FILE="$HOME/printer_data/moonraker.asvc"
if grep -Fxq "klipper-conf-git" "$ASVC_FILE" 2>/dev/null; then
    echo -e "${YLW}ℹ️  'klipper-conf-git' ist bereits in moonraker.asvc eingetragen.${NC}"
else
    echo -e "${YLW}➕ Trage 'klipper-conf-git' in moonraker.asvc ein...${NC}"
    echo "klipper-conf-git" >> "$ASVC_FILE"
    echo -e "${GRN}✅ moonraker.asvc aktualisiert.${NC}"
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
