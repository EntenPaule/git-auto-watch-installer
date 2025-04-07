# 🛠️ Git Auto Watch Installer

Ein vollautomatisches Bash-Skript, das bestimmte Verzeichnisse (z. B. Klipper-Konfigurationen) überwacht und Änderungen automatisch an ein privates GitHub-Repository pusht. Ideal für Raspberry Pi oder andere Debian-Systeme.

---

## 🔧 Voraussetzungen

- GitHub-Account
- Personal Access Token mit `repo`-Rechten: https://github.com/settings/tokens
- SSH-Zugang zu GitHub (optional: SSH-Key wird automatisch erstellt)
- Git, curl und inotify-tools installiert (wird vom Skript erledigt)

---

## 📁 Enthaltene Dateien

```text
setup.sh          → Hauptskript zur Einrichtung
.gitignore        → Ignoriert sensible Dateien wie .env
README.md         → Diese Anleitung
```

---

## 🚀 Installation

1. Repository klonen:

```bash
git clone git@github.com:DEIN-NUTZERNAME/git-auto-watch-installer.git
cd git-auto-watch-installer
```

2. Skript ausführbar machen:

```bash
chmod +x setup.sh
./setup.sh
```

3. Während des Setups wirst du gefragt nach:

- dem Namen des zu erstellenden GitHub-Repositories (Vorschlag: Hostname)
- deinem GitHub-PAT (Token)
- ob `updatemcu.sh` nach jedem Commit automatisch ausgeführt werden soll

---

## 🔧 Konfigurierbare Variablen (oben in `setup.sh`)

```bash
GIT_NAME="Dein Name"
GIT_EMAIL="deine@mailadresse.tld"
GITHUB_USER="deingithubnutzer"
```

---

## 📂 Standardmäßig überwachte Verzeichnisse

```text
~/printer_data/config
~/printer_data/database
```

---

## 🛠️ Optionale Funktion: MCU-Update

Wenn `~/printer_data/config/script/updatemcu.sh` existiert und du es beim Setup aktiviert hast, wird dieses Skript nach jedem erfolgreichen Push automatisch ausgeführt.

---

## 🔄 Autostart (systemd-Service)

```bash
systemctl --user status git-auto-watch.service
```

---

## 🔐 Sicherheit

- Der GitHub Token wird **nur lokal in `.env` gespeichert** (`chmod 600`)
- `.env` und `.log` sind durch `.gitignore` vom Git-Push ausgeschlossen
- GitHub-Zugriff erfolgt über SSH (`~/.ssh/id_ed25519`)
- Falls kein SSH-Key vorhanden ist, wird er automatisch erzeugt

---

## 📂 Dateistruktur nach Setup

```text
~/git-auto-watch/
├── .env                  → lokale Konfig mit Token & Optionen
├── git-auto-watch.sh     → Watch-Dienst
├── git-auto-watch.log    → Logs (nur wenn aktiviert)
├── .gitignore
```

---

## 🧼 Rückgängig machen / Deinstallation

### Systemd-Service stoppen & entfernen:

```bash
systemctl --user stop git-auto-watch.service
systemctl --user disable git-auto-watch.service
```

### Verzeichnisse löschen:

```bash
rm -rf ~/git-auto-watch
```

### Optional: SSH-Key löschen (wenn nur für dieses Projekt erstellt)

```bash
rm -f ~/.ssh/id_ed25519 ~/.ssh/id_ed25519.pub
```

### Git-Überwachung in Projektverzeichnissen entfernen:

```bash
cd ~/printer_data/config
rm -rf .git

cd ~/printer_data/database
rm -rf .git
```

---

## 📝 Lizenz

CC BY-SA 4.0 – freie Nutzung, Veränderung & Weitergabe erlaubt, unter Namensnennung und gleicher Lizenz.

---

**Erstellt mit ♥ von [@EntenPaule](https://github.com/EntenPaule)**


---

# 🛠️ Git Auto Watch Installer (EN)

A fully automated Bash setup script that watches specific directories (e.g., Klipper configurations) and pushes changes to a private GitHub repository. Ideal for Raspberry Pi or other Debian-based systems.

---

## 🔧 Requirements

- GitHub account
- Personal Access Token with `repo` scope: https://github.com/settings/tokens
- SSH access to GitHub (optional: SSH key is created automatically)
- Git, curl, and inotify-tools installed (setup script takes care of it)

---

## 📁 Included files

```text
setup.sh          → main setup script
.gitignore        → excludes sensitive files like .env
README.md         → this documentation
```

---

## 🚀 Installation

1. Clone the repository:

```bash
git clone git@github.com:YOUR-USERNAME/git-auto-watch-installer.git
cd git-auto-watch-installer
```

2. Make the script executable:

```bash
chmod +x setup.sh
./setup.sh
```

3. During setup you'll be asked for:

- repository name (default: hostname)
- your GitHub PAT (token)
- whether to run `updatemcu.sh` after each commit

---

## 🔧 Configurable variables (top of `setup.sh`)

```bash
GIT_NAME="Your Name"
GIT_EMAIL="your@email.tld"
GITHUB_USER="yourgithubusername"
```

---

## 📂 Watched directories by default

```text
~/printer_data/config
~/printer_data/database
```

---

## 🛠️ Optional: MCU update

If `~/printer_data/config/script/updatemcu.sh` exists and you enable it during setup, it will be executed after each push.

---

## 🔄 Autostart (systemd service)

```bash
systemctl --user status git-auto-watch.service
```

---

## 🔐 Security

- The GitHub token is stored **only locally** in `.env` (`chmod 600`)
- `.env` and `.log` are excluded via `.gitignore`
- GitHub access is via SSH (`~/.ssh/id_ed25519`)
- SSH key is auto-generated if missing

---

## 📂 Directory structure after setup

```text
~/git-auto-watch/
├── .env                  → local config with token & options
├── git-auto-watch.sh     → watcher script
├── git-auto-watch.log    → logs (if enabled)
├── .gitignore
```

---

## 🧼 Undo / Uninstall

### Stop and disable systemd service:

```bash
systemctl --user stop git-auto-watch.service
systemctl --user disable git-auto-watch.service
```

### Delete folders:

```bash
rm -rf ~/git-auto-watch
```

### Optional: delete SSH key (if created only for this project)

```bash
rm -f ~/.ssh/id_ed25519 ~/.ssh/id_ed25519.pub
```

### Remove Git tracking from watched directories:

```bash
cd ~/printer_data/config
rm -rf .git

cd ~/printer_data/database
rm -rf .git
```

---

## 📝 License

CC BY-SA 4.0 – free to use, modify & share with attribution and same license.

---

**Made with ♥ by [@EntenPaule](https://github.com/EntenPaule)**
