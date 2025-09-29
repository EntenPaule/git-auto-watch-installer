#!/bin/bash
# setup.sh – Git Auto Watch für Klipper-Configs (stabil, Home-basiert)

set -euo pipefail

# === Farben ===
GRN='\033[0;32m'; RED='\033[0;31m'; YLW='\033[1;33m'; BLU='\033[1;34m'; NC='\033[0m'

# === Defaults (kannst du anpassen) ===
GIT_NAME="EntenPaule"
GIT_EMAIL="git@entenpaule.local"
GITHUB_USER="EntenPaule"
BRANCH="master"                               # du hast GitHub auf master gestellt
WATCH_DIRS_DEFAULT=("printer_data/config" "printer_data/database")

# === Flags ===
FORCE=false
SYSTEM_WIDE=false
NO_PROMPT=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --force) FORCE=true; shift;;
    --system) SYSTEM_WIDE=true; shift;;
    --user) SYSTEM_WIDE=false; shift;;
    --yes|--non-interactive|-y) NO_PROMPT=true; shift;;
    *) echo "Unknown arg: $1"; exit 2;;
  esac
done

# === Echten User & Home ermitteln (auch unter sudo) ===
if ! REAL_USER="$(logname 2>/dev/null)"; then REAL_USER="$(whoami)"; fi
REAL_USER_HOME="$(eval echo "~${REAL_USER}")"

# === Pfade (alles im Home des echten Users) ===
BASE_DIR="$REAL_USER_HOME/git-auto-watch"
REPO_DIR="$BASE_DIR/local-repo"
ENV_FILE="$BASE_DIR/.env"
LOG_FILE="$BASE_DIR/git-auto-watch.log"
SCRIPT_FILE="$BASE_DIR/git-auto-watch.sh"

# === Vorhandene Config respektieren ===
if [[ -f "$ENV_FILE" && "$FORCE" == false ]]; then
  echo -e "${GRN}⚙️  Vorhandene Konfiguration gefunden – verwende $ENV_FILE.${NC}"
  echo -e "${YLW}⏩ Setup übersprungen (für Neuinstallation: $0 --force).${NC}"
  exit 0
fi

# === Pakete ===
echo -e "${YLW}📦 Pakete prüfen…${NC}"
sudo apt-get update -qq
need_install() { dpkg -s "$1" >/dev/null 2>&1 || return 0 && return 1; }
for p in git inotify-tools curl rsync; do
  if ! dpkg -s "$p" >/dev/null 2>&1; then
    echo -e "${YLW}➕ Installiere $p…${NC}"
    sudo apt-get install -y "$p"
  else
    echo -e "${GRN}✅ $p ok.${NC}"
  fi
done

# === SSH-Key bereitstellen (für SSH-Push) ===
if [[ ! -f "$REAL_USER_HOME/.ssh/id_ed25519" ]]; then
  echo -e "${YLW}🔐 Erstelle SSH-Key für GitHub…${NC}"
  sudo -u "$REAL_USER" ssh-keygen -t ed25519 -N "" -C "$GIT_EMAIL" -f "$REAL_USER_HOME/.ssh/id_ed25519"
  echo -e "${BLU}➡️  Diesen Public Key bei GitHub unter Settings → SSH keys hinzufügen:${NC}"
  cat "$REAL_USER_HOME/.ssh/id_ed25519.pub"
  if [[ "$NO_PROMPT" == false ]]; then
    read -rsp $'\nDrücke [Enter], wenn der Key hinzugefügt ist …\n'
  fi
fi

# === Git-User global setzen (harmlos, idempotent) ===
sudo -u "$REAL_USER" git config --global user.name  "$GIT_NAME"
sudo -u "$REAL_USER" git config --global user.email "$GIT_EMAIL"

# === Ziel-Repo-Name abfragen (Default = Hostname) ===
DEFAULT_REPO="$(hostname)"
if [[ "$NO_PROMPT" == true ]]; then
  REPO_NAME="$DEFAULT_REPO"
else
  read -rp "📦 GitHub-Repo-Name [${DEFAULT_REPO}]: " REPO_NAME
  REPO_NAME="${REPO_NAME:-$DEFAULT_REPO}"
fi
REMOTE_SSH="git@github.com:$GITHUB_USER/$REPO_NAME.git"

# === Watch-Verzeichnisse vorbereiten ===
WATCH_DIRS=()
for rel in "${WATCH_DIRS_DEFAULT[@]}"; do
  abs="$REAL_USER_HOME/$rel"
  WATCH_DIRS+=("$abs")
  if [[ ! -d "$abs" ]]; then
    echo -e "${YLW}📁 Erstelle Verzeichnis: $abs${NC}"
    mkdir -p "$abs"
  fi
  [[ -f "$abs/.gitkeep" ]] || touch "$abs/.gitkeep"
done

# === Clean & Verzeichnisse anlegen ===
rm -rf "$BASE_DIR"
mkdir -p "$REPO_DIR"

# === .env schreiben ===
WATCH_DIRS_STR="${WATCH_DIRS[*]}"
cat > "$ENV_FILE" <<EOF
# Auto-generiert von setup.sh
WATCH_DIRS="$WATCH_DIRS_STR"
REPO_DIR="$REPO_DIR"
GITHUB_USER="$GITHUB_USER"
REPO_NAME="$REPO_NAME"
BRANCH="$BRANCH"
ENABLE_LOGGING=true
ENABLE_DEBUG=true
USE_MCU_UPDATE=false
LOG_FILE="$LOG_FILE"
EOF
chmod 600 "$ENV_FILE"
echo -e "${GRN}✅ .env erstellt: $ENV_FILE${NC}"

# === Repo initialisieren (fallback ohne -b für alte Git-Versionen) ===
cd "$REPO_DIR"
if ! git init -b "$BRANCH" 2>/dev/null; then
  git init
  git symbolic-ref HEAD "refs/heads/$BRANCH" || true
  git checkout -B "$BRANCH" || git checkout -b "$BRANCH" || true
fi
# Remote setzen
if git remote | grep -q '^origin$'; then
  git remote set-url origin "$REMOTE_SSH"
else
  git remote add origin "$REMOTE_SSH"
fi

# === Initialen Inhalt aus Watch-Dirs spiegeln ===
echo -e "${YLW}📁 Synchronisiere initiale Dateien…${NC}"
for d in "${WATCH_DIRS[@]}"; do
  name="$(basename "$d")"
  mkdir -p "$REPO_DIR/$name"
  rsync -a --delete --checksum "$d/" "$REPO_DIR/$name/"
done
git add -A
git commit -m "Initial commit from setup" || true

# === Remote integrieren & pushen (non-fast-forward-sicher) ===
git fetch origin "$BRANCH" || true
git pull --rebase origin "$BRANCH" || true
git push -u origin "$BRANCH" || true

# === Watcher-Script schreiben (sourct .env per ENV_FILE Fallback) ===
cat > "$SCRIPT_FILE" <<'EOF'
#!/bin/bash
set -euo pipefail
: "${ENV_FILE:=$HOME/git-auto-watch/.env}"
# shellcheck disable=SC1090
source "$ENV_FILE"

log()   { [[ "${ENABLE_LOGGING:-true}" == "true" ]] && echo "[$(date '+%F %T')] $*" | tee -a "${LOG_FILE:-$HOME/git-auto-watch/git-auto-watch.log}"; }
debug() { [[ "${ENABLE_DEBUG:-true}"  == "true" ]] && log "DEBUG: $*"; }

# WATCH_DIRS kommt als Leerzeichen-separierte Liste
read -r -a WD_ARR <<< "${WATCH_DIRS:-}"
LOCKFILE="/tmp/git-auto-watch.lock"

ensure_repo() {
  cd "$REPO_DIR"
  CURRENT_BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")"
  if [[ "$CURRENT_BRANCH" != "$BRANCH" ]]; then
    git checkout -B "$BRANCH" || git checkout -b "$BRANCH" || true
  fi
}

sync_once() {
  cd "$REPO_DIR"
  for dir in "${WD_ARR[@]}"; do
    name="$(basename "$dir")"
    target="$REPO_DIR/$name"
    mkdir -p "$target"
    rsync -a --delete --checksum "$dir/" "$target/"
  done

  git add -A
  if git diff --cached --quiet; then
    debug "Keine Änderungen erkannt"
    return 0
  fi

  ts="$(date '+%F %T')"
  git commit -m "Auto-Update: $ts"
  if ! git push origin "$BRANCH" > /dev/null 2>&1; then
    log "Push fehlgeschlagen – rebase & retry"
    git pull --rebase origin "$BRANCH" || true
    git push origin "$BRANCH" || true
  fi
  log "Änderung gepusht: $ts"

  if [[ "${USE_MCU_UPDATE:-false}" == "true" ]]; then
    MCU="$HOME/printer_data/config/script/updatemcu.sh"
    [[ -x "$MCU" ]] && "$MCU" && log "MCU-Skript ausgeführt"
  fi
}

log "Starte Überwachung…"
ensure_repo

while true; do
  EXISTING=()
  for d in "${WD_ARR[@]}"; do [[ -d "$d" ]] && EXISTING+=("$d"); done
  if [[ "${#EXISTING[@]}" -eq 0 ]]; then
    log "Keine gültigen Watch-Verzeichnisse – warte 10s."
    sleep 10
    continue
  fi

  inotifywait -r -e modify,create,delete,move "${EXISTING[@]}" >/dev/null 2>&1 || true
  (
    flock -n 9 || exit 1
    sync_once
  ) 9>"$LOCKFILE"
done
EOF
sed -i 's/\r$//' "$SCRIPT_FILE"
chmod +x "$SCRIPT_FILE"

# === systemd-Service schreiben (systemweit oder user) ===
if [[ "$SYSTEM_WIDE" == true ]]; then
  SERVICE_FILE="/etc/systemd/system/klipper-conf-git.service"
  sudo tee "$SERVICE_FILE" >/dev/null <<EOF
[Unit]
Description=Git Auto Watcher für Klipper-Config (systemweit)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=$REAL_USER
WorkingDirectory=$BASE_DIR
Environment=ENV_FILE=$ENV_FILE
ExecStart=$SCRIPT_FILE
Restart=always

[Install]
WantedBy=multi-user.target
EOF
  sudo systemctl daemon-reload
  sudo systemctl enable --now klipper-conf-git.service
else
  SERVICE_FILE="$REAL_USER_HOME/.config/systemd/user/klipper-conf-git.service"
  mkdir -p "$(dirname "$SERVICE_FILE")"
  cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Git Auto Watcher für Klipper-Config (User)
After=default.target

[Service]
Type=simple
WorkingDirectory=$BASE_DIR
Environment=ENV_FILE=$ENV_FILE
ExecStart=$SCRIPT_FILE
Restart=always

[Install]
WantedBy=default.target
EOF
  systemctl --user daemon-reload
  systemctl --user enable --now klipper-conf-git.service
fi

# === Moonraker Update-Manager (lokales Repo) ===
MOON_CFG="$REAL_USER_HOME/printer_data/config/moonraker.conf"
INSTALLER_NAME="klipper-conf-git"
if ! grep -q "^\[update_manager $INSTALLER_NAME\]" "$MOON_CFG" 2>/dev/null; then
  echo -e "${YLW}➕ Trage Update-Manager in moonraker.conf ein…${NC}"
  cat >> "$MOON_CFG" <<EOF

[update_manager $INSTALLER_NAME]
type: git_repo
path: $REPO_DIR
origin: $REMOTE_SSH
primary_branch: $BRANCH
EOF
  sudo systemctl restart moonraker.service || true
else
  echo -e "${GRN}ℹ️  Update-Manager-Eintrag existiert bereits.${NC}"
fi

# === moonraker.asvc (Service-Verwaltung) ===
ASVC_FILE="$REAL_USER_HOME/printer_data/moonraker.asvc"
if ! grep -Fxq "klipper-conf-git" "$ASVC_FILE" 2>/dev/null; then
  echo "klipper-conf-git" >> "$ASVC_FILE" 2>/dev/null || true
fi

# === Ergebnis ===
if [[ "$SYSTEM_WIDE" == true ]]; then
  STATUS="$(sudo systemctl is-active klipper-conf-git.service || true)"
else
  STATUS="$(systemctl --user is-active klipper-conf-git.service || true)"
fi
[[ "$STATUS" == "active" ]] && ok="🟢" || ok="🔴"
echo -e "\n${ok} Setup fertig."
echo -e "📦 Repo:        ${BLU}$GITHUB_USER/$REPO_NAME ($BRANCH)${NC}"
echo -e "📁 Watch:       ${BLU}${WATCH_DIRS[*]}${NC}"
echo -e "📝 Logfile:     ${BLU}$LOG_FILE${NC}"
echo -e "📂 Repo-Ordner: ${BLU}$REPO_DIR${NC}"
echo -e "🧩 Service:     ${BLU}$( [[ "$SYSTEM_WIDE" == true ]] && echo systemweit || echo user )${NC}"
echo
if [[ "$SYSTEM_WIDE" == true ]]; then
  echo -e "🔍 Logs:  ${YLW}sudo journalctl -u klipper-conf-git.service -n 100 --no-pager${NC}"
else
  echo -e "🔍 Logs:  ${YLW}journalctl --user -u klipper-conf-git.service -n 100 --no-pager${NC}"
fi
