#!/bin/bash
# ============================================================
#  Interactive LAMP / LEMP Stack Installer
#  OS      : Ubuntu 20.04 / 22.04 / 24.04 / Debian 11-12
#  Author  : SysAdmin Pro Script
#  Version : 2.0
# ============================================================

set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

# ── Colors ──────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

# ── Helpers ──────────────────────────────────────────────────
info()    { echo -e "${CYAN}${BOLD}[INFO]${RESET}  $*"; }
success() { echo -e "${GREEN}${BOLD}[  OK]${RESET}  $*"; }
warn()    { echo -e "${YELLOW}${BOLD}[WARN]${RESET}  $*"; }
error()   { echo -e "${RED}${BOLD}[FAIL]${RESET}  $*"; exit 1; }
step()    { echo -e "\n${MAGENTA}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"; \
            echo -e "${MAGENTA}${BOLD}  $*${RESET}"; \
            echo -e "${MAGENTA}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"; }
ask()     { echo -e "${YELLOW}${BOLD}[ASK ]${RESET}  $*"; }
divider() { echo -e "${DIM}────────────────────────────────────────────────${RESET}"; }

spinner() {
    local pid=$1 msg=$2
    local spin='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    local i=0
    while kill -0 "$pid" 2>/dev/null; do
        i=$(( (i+1) % 10 ))
        printf "\r${CYAN}  ${spin:$i:1}  ${msg}...${RESET}"
        sleep 0.1
    done
    printf "\r${GREEN}  ✔  ${msg} — Done!${RESET}\n"
}

run_with_spinner() {
    local msg="$1"; shift
    "$@" &>/tmp/stack_install.log &
    spinner $! "$msg"
}

check_service() {
    local svc="$1" label="$2"
    if systemctl is-active --quiet "$svc"; then
        success "$label is running ✔"
    else
        warn "$label is NOT running — check: journalctl -u $svc -n 20"
    fi
}

confirm() {
    local prompt="$1"
    while true; do
        ask "$prompt ${DIM}[y/n]${RESET}"
        read -r yn
        case "$yn" in
            [Yy]*) return 0 ;;
            [Nn]*) return 1 ;;
            *)     echo "  Please enter y or n." ;;
        esac
    done
}

pick_one() {
    local prompt="$1"; shift
    local options=("$@")
    ask "$prompt"
    for i in "${!options[@]}"; do
        echo -e "  ${BOLD}$((i+1)))${RESET} ${options[$i]}"
    done
    while true; do
        read -rp "  Enter number [1-${#options[@]}]: " choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#options[@]} )); then
            PICK="${options[$((choice-1))]}"
            return
        fi
        echo "  Invalid choice, try again."
    done
}

# ── Root Check ───────────────────────────────────────────────
if [[ "$EUID" -ne 0 ]]; then
    error "Run this script as root:  sudo bash $0"
fi

# ── Banner ───────────────────────────────────────────────────
clear
echo -e "${BLUE}${BOLD}"
cat << 'EOF'
  ██╗      █████╗ ███╗   ███╗██████╗     ██╗      ███████╗███╗   ███╗██████╗
  ██║     ██╔══██╗████╗ ████║██╔══██╗    ██║      ██╔════╝████╗ ████║██╔══██╗
  ██║     ███████║██╔████╔██║██████╔╝    ██║      █████╗  ██╔████╔██║██████╔╝
  ██║     ██╔══██║██║╚██╔╝██║██╔═══╝     ██║      ██╔══╝  ██║╚██╔╝██║██╔═══╝
  ███████╗██║  ██║██║ ╚═╝ ██║██║         ███████╗ ███████╗██║ ╚═╝ ██║██║
  ╚══════╝╚═╝  ╚═╝╚═╝     ╚═╝╚═╝         ╚══════╝ ╚══════╝╚═╝     ╚═╝╚═╝
EOF
echo -e "${RESET}"
echo -e "${DIM}  Interactive Stack Installer  ·  Ubuntu / Debian  ·  v2.0${RESET}"
divider
echo ""

# ════════════════════════════════════════════════════════════
#  SECTION 0 — OS Detection & Version Selection
# ════════════════════════════════════════════════════════════
step "OS DETECTION"

SUPPORTED_OS=(
    "Ubuntu 24.04 (Noble)"
    "Ubuntu 22.04 (Jammy)"
    "Ubuntu 20.04 (Focal)"
    "Debian 12 (Bookworm)"
    "Debian 11 (Bullseye)"
)

# Auto-detect
DETECTED_NAME="Unknown"
DETECTED_ID="unknown"
DETECTED_CODENAME="unknown"

if [[ -f /etc/os-release ]]; then
    source /etc/os-release
    DETECTED_NAME="${PRETTY_NAME:-$NAME}"
    DETECTED_ID="${ID:-unknown}"
    DETECTED_CODENAME="${VERSION_CODENAME:-unknown}"
fi

info "Auto-detected: ${BOLD}${DETECTED_NAME}${RESET}"
echo ""

if confirm "Is this correct?"; then
    OS_ID="$DETECTED_ID"
    UBUNTU_CODENAME="$DETECTED_CODENAME"
    OS_NAME="$DETECTED_NAME"
else
    echo ""
    pick_one "Select your OS + version:" "${SUPPORTED_OS[@]}"
    OS_NAME="$PICK"
    case "$OS_NAME" in
        "Ubuntu 24.04 (Noble)")   OS_ID="ubuntu"; UBUNTU_CODENAME="noble"    ;;
        "Ubuntu 22.04 (Jammy)")   OS_ID="ubuntu"; UBUNTU_CODENAME="jammy"    ;;
        "Ubuntu 20.04 (Focal)")   OS_ID="ubuntu"; UBUNTU_CODENAME="focal"    ;;
        "Debian 12 (Bookworm)")   OS_ID="debian"; UBUNTU_CODENAME="bookworm" ;;
        "Debian 11 (Bullseye)")   OS_ID="debian"; UBUNTU_CODENAME="bullseye" ;;
    esac
fi

case "$OS_ID" in
    ubuntu|debian) : ;;
    *) error "Unsupported OS: $OS_ID — Use the AlmaLinux script for RHEL-based systems." ;;
esac

success "Proceeding with: ${BOLD}${OS_NAME}${RESET}  (Codename: ${UBUNTU_CODENAME})"
info "Codename: ${UBUNTU_CODENAME}"


# ════════════════════════════════════════════════════════════
#  SECTION 0b — Pre-flight
# ════════════════════════════════════════════════════════════
step "PRE-FLIGHT CHECKS"

RAM_MB=$(free -m | awk '/^Mem:/{print $2}')
info "RAM: ${RAM_MB} MB"
(( RAM_MB < 1024 )) && warn "Less than 1GB RAM detected."

DISK_FREE=$(df -BG / | awk 'NR==2{gsub("G",""); print $4}')
info "Free disk on /: ${DISK_FREE}G"
(( DISK_FREE < 10 )) && warn "Less than 10GB free disk space."

if curl -s --max-time 5 https://google.com &>/dev/null; then
    success "Internet connectivity OK"
else
    error "No internet access. Aborting."
fi

echo ""
confirm "Pre-flight checks complete. Continue with installation?" || exit 0

# ════════════════════════════════════════════════════════════
#  SECTION 1 — System Update
# ════════════════════════════════════════════════════════════
step "STEP 1 — System Update & Base Tools"

if confirm "Update system packages now? (Recommended)"; then
    run_with_spinner "Updating system" apt update && apt upgrade -y
    success "System updated"
fi

run_with_spinner "Installing base tools" apt install -y \
    wget curl vim nano git zip unzip tar \
    net-tools dnsutils lsof htop tree \
    ufw software-properties-common gnupg2 ca-certificates lsb-release apt-transport-https

ufw --force enable &>/dev/null
ufw allow OpenSSH &>/dev/null
success "UFW enabled"

# ════════════════════════════════════════════════════════════
#  SECTION 2 — Web Server
# ════════════════════════════════════════════════════════════
step "STEP 2 — Web Server"

WEB_SERVER=""
pick_one "Which web server do you want to install?" \
    "Apache2" \
    "Nginx" \
    "Both Apache2 + Nginx (different ports)"
WEB_SERVER="$PICK"

case "$WEB_SERVER" in
    "Apache2")
        run_with_spinner "Installing Apache2" apt install -y apache2
        systemctl enable --now apache2
        ufw allow 'Apache Full' &>/dev/null
        a2enmod rewrite headers ssl &>/dev/null
        systemctl restart apache2
        check_service apache2 "Apache2"
        ;;
    "Nginx")
        run_with_spinner "Installing Nginx" apt install -y nginx
        systemctl enable --now nginx
        ufw allow 'Nginx Full' &>/dev/null
        check_service nginx "Nginx"
        ;;
    "Both Apache2 + Nginx (different ports)")
        run_with_spinner "Installing Apache2 + Nginx" apt install -y apache2 nginx
        # Nginx on 8080
        sed -i 's/listen 80 default_server;/listen 8080 default_server;/' \
            /etc/nginx/sites-available/default 2>/dev/null || true
        sed -i 's/listen \[::\]:80 default_server;/listen [::]:8080 default_server;/' \
            /etc/nginx/sites-available/default 2>/dev/null || true
        systemctl enable --now apache2
        systemctl enable --now nginx
        ufw allow 80/tcp &>/dev/null
        ufw allow 443/tcp &>/dev/null
        ufw allow 8080/tcp &>/dev/null
        a2enmod rewrite headers ssl &>/dev/null
        systemctl restart apache2
        systemctl restart nginx
        check_service apache2 "Apache2"
        check_service nginx "Nginx (port 8080)"
        ;;
esac

# ════════════════════════════════════════════════════════════
#  SECTION 3 — PHP
# ════════════════════════════════════════════════════════════
step "STEP 3 — PHP"

if confirm "Install PHP?"; then
    # Add Ondrej PHP PPA (Ubuntu) or sury (Debian)
    if [[ "$ID" == "ubuntu" ]]; then
        run_with_spinner "Adding PHP PPA (ondrej/php)" add-apt-repository -y ppa:ondrej/php
    else
        curl -sSL https://packages.sury.org/php/apt.gpg | gpg --dearmor \
            -o /usr/share/keyrings/php-sury.gpg
        echo "deb [signed-by=/usr/share/keyrings/php-sury.gpg] https://packages.sury.org/php/ ${UBUNTU_CODENAME} main" \
            > /etc/apt/sources.list.d/php.list
    fi
    run_with_spinner "Refreshing package lists" apt update

    pick_one "Select default PHP version:" \
        "PHP 8.4 (Latest Stable — Recommended)" \
        "PHP 8.3" \
        "PHP 8.2" \
        "PHP 8.1"
    PHP_DEFAULT="$PICK"
    PHP_VER=$(echo "$PHP_DEFAULT" | grep -oP '\d+\.\d+')

    COMMON_EXTS="php${PHP_VER} php${PHP_VER}-cli php${PHP_VER}-fpm \
        php${PHP_VER}-mysql php${PHP_VER}-gd php${PHP_VER}-mbstring \
        php${PHP_VER}-xml php${PHP_VER}-opcache php${PHP_VER}-zip \
        php${PHP_VER}-curl php${PHP_VER}-intl php${PHP_VER}-bcmath"

    if [[ "$WEB_SERVER" == *"Apache"* ]] || [[ "$WEB_SERVER" == *"Both"* ]]; then
        COMMON_EXTS="$COMMON_EXTS libapache2-mod-php${PHP_VER}"
    fi

    run_with_spinner "Installing PHP ${PHP_VER}" apt install -y $COMMON_EXTS
    systemctl enable --now php${PHP_VER}-fpm
    check_service php${PHP_VER}-fpm "PHP-FPM ${PHP_VER}"

    # Multi-version
    echo ""
    info "Additional PHP versions available: 7.4, 8.0, 8.1, 8.2, 8.3, 8.4"
    if confirm "Install additional PHP versions?"; then
        for VER in 7.4 8.0 8.1 8.2 8.3; do
            if [[ "$VER" == "$PHP_VER" ]]; then continue; fi
            if confirm "  Install PHP ${VER}?"; then
                run_with_spinner "Installing PHP ${VER}" apt install -y \
                    php${VER} php${VER}-cli php${VER}-fpm \
                    php${VER}-mysql php${VER}-mbstring \
                    php${VER}-xml php${VER}-gd php${VER}-zip php${VER}-curl
                systemctl enable --now php${VER}-fpm
                check_service php${VER}-fpm "PHP-FPM ${VER}"
            fi
        done
    fi

    # PHP hardening
    PHP_INI="/etc/php/${PHP_VER}/fpm/php.ini"
    if [[ -f "$PHP_INI" ]]; then
        sed -i 's/^expose_php = On/expose_php = Off/' "$PHP_INI"
        sed -i 's/^display_errors = On/display_errors = Off/' "$PHP_INI"
        sed -i 's/^allow_url_fopen = On/allow_url_fopen = Off/' "$PHP_INI"
        systemctl restart php${PHP_VER}-fpm
        success "PHP hardened (expose_php off, display_errors off)"
    fi
fi

# ════════════════════════════════════════════════════════════
#  SECTION 4 — MySQL / MariaDB
# ════════════════════════════════════════════════════════════
step "STEP 4 — MySQL / MariaDB"

if confirm "Install MySQL or MariaDB?"; then
    pick_one "Select database server:" \
        "MySQL 8.4 LTS (Recommended)" \
        "MySQL 8.0" \
        "MariaDB 10.11 LTS" \
        "MariaDB 11.x (Latest)"
    MYSQL_CHOICE="$PICK"

    case "$MYSQL_CHOICE" in
        "MySQL 8.4 LTS (Recommended)")
            wget -q https://repo.mysql.com/mysql-apt-config_0.8.30-1_all.deb \
                -O /tmp/mysql-apt.deb
            MYSQL_SERVER_DEFAULT="mysql-8.4-lts" dpkg -i /tmp/mysql-apt.deb &>/dev/null || true
            run_with_spinner "Refreshing apt" apt update
            run_with_spinner "Installing MySQL 8.4" apt install -y mysql-server
            ;;
        "MySQL 8.0")
            run_with_spinner "Installing MySQL 8.0" apt install -y mysql-server
            ;;
        "MariaDB 10.11 LTS")
            curl -LsS https://downloads.mariadb.com/MariaDB/mariadb_repo_setup \
                | bash -s -- --mariadb-server-version="mariadb-10.11" &>/tmp/stack_install.log
            run_with_spinner "Installing MariaDB 10.11" apt install -y mariadb-server mariadb-client
            ;;
        "MariaDB 11.x (Latest)")
            curl -LsS https://downloads.mariadb.com/MariaDB/mariadb_repo_setup \
                | bash -s -- --mariadb-server-version="mariadb-11" &>/tmp/stack_install.log
            run_with_spinner "Installing MariaDB 11" apt install -y mariadb-server mariadb-client
            ;;
    esac

    if [[ "$MYSQL_CHOICE" == *"MariaDB"* ]]; then
        systemctl enable --now mariadb
        check_service mariadb "MariaDB"
    else
        systemctl enable --now mysql
        check_service mysql "MySQL"
    fi

    warn "Run:  mysql_secure_installation  to set root password and harden MySQL"
fi

# ════════════════════════════════════════════════════════════
#  SECTION 5 — MongoDB
# ════════════════════════════════════════════════════════════
step "STEP 5 — MongoDB"

if confirm "Install MongoDB?"; then
    pick_one "Select MongoDB version:" \
        "MongoDB 8.0 (Latest Stable)" \
        "MongoDB 7.0 (LTS)"
    MONGO_VER="$PICK"
    MONGO_NUM=$(echo "$MONGO_VER" | grep -oP '\d+\.\d+')

    curl -fsSL https://www.mongodb.org/static/pgp/server-${MONGO_NUM}.asc | \
        gpg --dearmor -o /usr/share/keyrings/mongodb-server.gpg

    echo "deb [ arch=amd64,arm64 signed-by=/usr/share/keyrings/mongodb-server.gpg ] \
https://repo.mongodb.org/apt/ubuntu ${UBUNTU_CODENAME}/mongodb-org/${MONGO_NUM} multiverse" \
        > /etc/apt/sources.list.d/mongodb-org-${MONGO_NUM}.list

    run_with_spinner "Refreshing apt" apt update
    run_with_spinner "Installing MongoDB ${MONGO_NUM}" apt install -y mongodb-org

    ask "MongoDB default port is 27017 (change recommended for security)"
    read -rp "  Enter custom port [default: 35001]: " MONGO_PORT
    MONGO_PORT="${MONGO_PORT:-35001}"

    sed -i "s/port: 27017/port: ${MONGO_PORT}/" /etc/mongod.conf
    systemctl enable --now mongod
    check_service mongod "MongoDB"
    ufw allow ${MONGO_PORT}/tcp &>/dev/null

    success "MongoDB running on port ${MONGO_PORT} (localhost only)"
    echo "MONGODB_PORT=${MONGO_PORT}" >> /root/stack-credentials.txt
    warn "Create admin user BEFORE enabling auth (see documentation)"
fi

# ════════════════════════════════════════════════════════════
#  SECTION 6 — PostgreSQL
# ════════════════════════════════════════════════════════════
step "STEP 6 — PostgreSQL"

if confirm "Install PostgreSQL?"; then
    pick_one "Select PostgreSQL version:" \
        "PostgreSQL 18 (Latest)" \
        "PostgreSQL 17" \
        "PostgreSQL 16 (LTS)"
    PG_VER="$PICK"
    PG_NUM=$(echo "$PG_VER" | grep -oP '\d+' | head -1)

    curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc | \
        gpg --dearmor -o /usr/share/keyrings/postgresql.gpg
    echo "deb [signed-by=/usr/share/keyrings/postgresql.gpg] \
https://apt.postgresql.org/pub/repos/apt ${UBUNTU_CODENAME}-pgdg main" \
        > /etc/apt/sources.list.d/pgdg.list

    run_with_spinner "Refreshing apt" apt update
    run_with_spinner "Installing PostgreSQL ${PG_NUM}" apt install -y \
        postgresql-${PG_NUM} postgresql-client-${PG_NUM}
    systemctl enable --now postgresql
    check_service postgresql "PostgreSQL ${PG_NUM}"
    ufw allow 5432/tcp &>/dev/null

    warn "Set postgres user password: sudo -u postgres psql -c \"ALTER USER postgres PASSWORD 'YOURPASS';\""
fi

# ════════════════════════════════════════════════════════════
#  SECTION 7 — SSL (Let's Encrypt)
# ════════════════════════════════════════════════════════════
step "STEP 7 — SSL via Let's Encrypt (Certbot)"

info "Installing Certbot for Let's Encrypt SSL..."
run_with_spinner "Installing Certbot" apt install -y certbot python3-certbot-apache python3-certbot-nginx
success "Certbot installed"
info "Apache usage : certbot --apache  -d yourdomain.com"
info "Nginx usage  : certbot --nginx   -d yourdomain.com"
info "Auto-renewal : certbot renew --dry-run"

# ════════════════════════════════════════════════════════════
#  FINAL VERIFICATION
# ════════════════════════════════════════════════════════════
step "FINAL VERIFICATION"

echo -e "\n${BOLD}  Service Status:${RESET}"
divider

declare -A SERVICES=(
    ["apache2"]="Apache2"
    ["nginx"]="Nginx"
    ["mysql"]="MySQL"
    ["mariadb"]="MariaDB"
    ["mongod"]="MongoDB"
    ["postgresql"]="PostgreSQL"
)

for svc in "${!SERVICES[@]}"; do
    if systemctl list-units --full -all 2>/dev/null | grep -q "${svc}.service"; then
        if systemctl is-active --quiet "$svc" 2>/dev/null; then
            echo -e "  ${GREEN}✔${RESET}  ${SERVICES[$svc]}"
        else
            echo -e "  ${RED}✘${RESET}  ${SERVICES[$svc]} ${DIM}(installed but not running)${RESET}"
        fi
    fi
done

divider
echo -e "\n${BOLD}  Open Ports:${RESET}"
ss -tlnp | grep -E ':80|:443|:3306|:5432|:8080|:35001' | \
    awk '{print "  " $4}' | sort -u

divider
echo -e "\n${BOLD}  Versions:${RESET}"
command -v apache2 &>/dev/null && echo -e "  Apache  : $(apache2 -v 2>&1 | head -1)"
command -v nginx   &>/dev/null && echo -e "  Nginx   : $(nginx -v 2>&1)"
command -v php     &>/dev/null && echo -e "  PHP     : $(php -r 'echo PHP_VERSION;')"
command -v mysql   &>/dev/null && echo -e "  MySQL   : $(mysql --version 2>&1)"
command -v psql    &>/dev/null && echo -e "  Postgres: $(psql --version 2>&1)"
command -v mongod  &>/dev/null && echo -e "  MongoDB : $(mongod --version 2>&1 | head -1)"

echo ""
echo -e "${GREEN}${BOLD}"
cat << 'EOF'
  ╔══════════════════════════════════════════════════════╗
  ║   ✅  STACK INSTALLATION COMPLETE — HAVE FUN!       ║
  ╚══════════════════════════════════════════════════════╝
EOF
echo -e "${RESET}"
echo -e "${DIM}  Credentials saved to: /root/stack-credentials.txt${RESET}"
echo -e "${DIM}  Logs:                 /tmp/stack_install.log${RESET}"
echo -e "${DIM}  Next steps:           Set DB passwords, configure vhosts, enable SSL${RESET}"
echo ""
