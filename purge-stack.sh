#!/bin/bash
# ============================================================
#  FULL STACK PURGE — Ubuntu / Debian
#  Removes: Apache, Nginx, PHP, MySQL, MariaDB, MongoDB, PostgreSQL, Node.js, Python, PM2, Certbot
# ============================================================

[[ "$EUID" -ne 0 ]] && { echo "Run as root: sudo bash purge-stack.sh"; exit 1; }

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; DIM='\033[2m'; RESET='\033[0m'

step()  { echo -e "\n${CYAN}${BOLD}[$1/9]${RESET} $2..."; }
ok()    { echo -e "  ${GREEN}✔${RESET}  $1"; }
warn()  { echo -e "  ${YELLOW}⚠${RESET}  $1"; }

echo -e "${RED}${BOLD}"
cat << 'BANNER'
  ██████╗ ██╗   ██╗██████╗  ██████╗ ███████╗
  ██╔══██╗██║   ██║██╔══██╗██╔════╝ ██╔════╝
  ██████╔╝██║   ██║██████╔╝██║  ███╗█████╗
  ██╔═══╝ ██║   ██║██╔══██╗██║   ██║██╔══╝
  ██║     ╚██████╔╝██║  ██║╚██████╔╝███████╗
  ╚═╝      ╚═════╝ ╚═╝  ╚═╝ ╚═════╝ ╚══════╝
  FULL STACK PURGE — Ubuntu / Debian
BANNER
echo -e "${RESET}"
echo -e "${YELLOW}${BOLD}  ⚠  WARNING: This will DELETE all data in MySQL, MongoDB, PostgreSQL!${RESET}"
echo -e "${DIM}  Backups lena: mysqldump / mongodump / pg_dump${RESET}"
echo ""
read -rp "  Type YES to confirm purge: " confirm
[[ "$confirm" != "YES" ]] && { echo "Aborted."; exit 0; }

# ── 1. PHP ──────────────────────────────────────────────────
step 1 "Purging PHP (all versions 7.x + 8.x)"
systemctl stop 'php*-fpm' 2>/dev/null || true
apt-get purge -y 'php*'                2>/dev/null || true
apt-get autoremove -y                  2>/dev/null || true
add-apt-repository --remove -y ppa:ondrej/php 2>/dev/null || true
rm -f  /etc/apt/sources.list.d/ondrej-ubuntu-php-*.list
rm -f  /etc/apt/sources.list.d/php-sury.list
rm -rf /etc/php/ /var/lib/php/ /var/log/php* /run/php/
ok "PHP purged"

# ── 2. Apache ───────────────────────────────────────────────
step 2 "Purging Apache"
systemctl stop apache2 2>/dev/null || true
apt-get purge -y 'apache2*' 'libapache2-mod-*' 2>/dev/null || true
apt-get autoremove -y                           2>/dev/null || true
rm -rf /etc/apache2/ /var/log/apache2/ /var/run/apache2/
ok "Apache purged"

# ── 3. Nginx ────────────────────────────────────────────────
step 3 "Purging Nginx"
systemctl stop nginx 2>/dev/null || true
apt-get purge -y 'nginx*'  2>/dev/null || true
apt-get autoremove -y      2>/dev/null || true
rm -rf /etc/nginx/ /var/log/nginx/ /var/run/nginx/
ok "Nginx purged"

# ── 4. MySQL / MariaDB ──────────────────────────────────────
step 4 "Purging MySQL / MariaDB (DATA DELETED)"
systemctl stop mysql mysqld mariadb 2>/dev/null || true
apt-get purge -y 'mysql*' 'mariadb*' 2>/dev/null || true
apt-get autoremove -y                2>/dev/null || true
rm -rf /etc/mysql/ /var/lib/mysql/ /var/log/mysql* /var/run/mysqld/
rm -f  /etc/apt/sources.list.d/mysql*.list
rm -f  /etc/apt/sources.list.d/mariadb*.list
rm -f  /usr/share/keyrings/mysql*.gpg
rm -f  /tmp/mysql-apt.deb
ok "MySQL / MariaDB purged"

# ── 5. MongoDB ──────────────────────────────────────────────
step 5 "Purging MongoDB (DATA DELETED)"
systemctl stop mongod 2>/dev/null || true
apt-get purge -y 'mongodb*' 'mongod*' 2>/dev/null || true
apt-get autoremove -y                 2>/dev/null || true
rm -rf /etc/mongod.conf /var/lib/mongodb/ /var/log/mongodb/ /tmp/mongodb-*.sock
rm -f  /etc/apt/sources.list.d/mongodb*.list
rm -f  /usr/share/keyrings/mongodb*.gpg
ok "MongoDB purged"

# ── 6. PostgreSQL ───────────────────────────────────────────
step 6 "Purging PostgreSQL (DATA DELETED)"
systemctl stop postgresql 2>/dev/null || true
apt-get purge -y 'postgresql*' 2>/dev/null || true
apt-get autoremove -y          2>/dev/null || true
rm -rf /etc/postgresql/ /var/lib/postgresql/ /var/log/postgresql/ /var/run/postgresql/
rm -f  /etc/apt/sources.list.d/pgdg.list
rm -f  /usr/share/keyrings/postgresql.gpg
ok "PostgreSQL purged"

# ── 7. Node.js (nvm) + PM2 ─────────────────────────────────
step 7 "Purging Node.js (nvm) + PM2"
# Stop and remove PM2 from all users
for user_home in /root /home/*; do
    [[ -d "$user_home" ]] || continue
    NVM_DIR="$user_home/.nvm"
    if [[ -d "$NVM_DIR" ]]; then
        uname=$(basename "$user_home")
        # Remove PM2 startup hook
        pm2 delete all 2>/dev/null || true
        pm2 unstartup systemd 2>/dev/null || true
        systemctl disable pm2-root 2>/dev/null || true
        systemctl stop pm2-root 2>/dev/null || true
        rm -f /etc/systemd/system/pm2-*.service
        # Wipe entire nvm directory (all node versions + npm + pm2 inside it)
        rm -rf "$NVM_DIR"
        ok "nvm + all Node versions + PM2 removed for $uname"
    fi
done
# Clean up nvm lines from shell rc files
for rcfile in /root/.bashrc /root/.bash_profile /root/.profile /root/.zshrc; do
    [[ -f "$rcfile" ]] && sed -i '/NVM_DIR\|nvm\.sh\|nvm completion/d' "$rcfile"
done
# Remove any system-level node/npm/pm2 installs
apt-get purge -y 'nodejs*' 'npm*' 2>/dev/null || true
apt-get autoremove -y            2>/dev/null || true
rm -f /etc/apt/sources.list.d/nodesource*.list
rm -f /usr/share/keyrings/nodesource*.gpg
rm -rf /usr/local/lib/node_modules/pm2
rm -f /usr/local/bin/pm2 /usr/local/bin/node /usr/local/bin/npm /usr/local/bin/npx
ok "Node.js + PM2 fully purged"

# ── 8. Python (deadsnakes versions only — keeps Ubuntu system 3.12) ──
step 8 "Purging extra Python versions (3.9 / 3.10 / 3.11 / 3.13 / 3.14)"
# Remove update-alternatives entries for bare `python`
update-alternatives --remove-all python 2>/dev/null || true
# Purge deadsnakes-installed versions (safe list — skip 3.12 = Ubuntu system python3)
PYTHON_EXTRA=(3.9 3.10 3.11 3.13 3.14)
for ver in "${PYTHON_EXTRA[@]}"; do
    apt-get purge -y \
        "python${ver}" "python${ver}-dev" "python${ver}-venv" \
        "python${ver}-distutils" "python${ver}-lib2to3" "python${ver}-minimal" \
        2>/dev/null || true
done
apt-get autoremove -y 2>/dev/null || true
# Remove deadsnakes PPA
add-apt-repository --remove -y ppa:deadsnakes/python 2>/dev/null || true
rm -f /etc/apt/sources.list.d/deadsnakes-ubuntu-ppa-*.list
rm -f /usr/bin/python  # remove bare symlink set by update-alternatives
ok "Extra Python versions purged (system python3/3.12 preserved)"

# ── 9. Certbot ──────────────────────────────────────────────
step 9 "Purging Certbot / Let's Encrypt"
systemctl stop certbot 2>/dev/null || true
apt-get purge -y 'certbot*' 'python3-certbot*' 2>/dev/null || true
apt-get autoremove -y                           2>/dev/null || true
rm -rf /etc/letsencrypt/ /var/log/letsencrypt/ /var/lib/letsencrypt/
ok "Certbot purged"

# ── Final cleanup ────────────────────────────────────────────
echo -e "\n${CYAN}${BOLD}[+]${RESET} Final apt cleanup..."
apt-get autoclean -y  2>/dev/null
apt-get update        2>/dev/null
systemctl daemon-reload

echo ""
echo -e "${GREEN}${BOLD}"
cat << 'DONE'
  ╔══════════════════════════════════════════════════════╗
  ║   ✅  SERVER FULLY PURGED — CLEAN SLATE READY!      ║
  ╚══════════════════════════════════════════════════════╝
DONE
echo -e "${RESET}"
echo -e "  ${DIM}Now run: sudo bash setup-ubuntu.sh${RESET}"
echo ""
