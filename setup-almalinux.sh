#!/bin/bash
# ============================================================
#  Interactive LAMP / LEMP Stack Installer
#  OS      : AlmaLinux 8/9/10 · RHEL 8/9/10 · Rocky 8/9
#  Version : 3.0
# ============================================================

set -euo pipefail

# ── Colors ──────────────────────────────────────────────────
RED='\033[0;31m';  GREEN='\033[0;32m';  YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m';   MAGENTA='\033[0;35m'
BOLD='\033[1m';    DIM='\033[2m';        RESET='\033[0m'

info()    { echo -e "${CYAN}${BOLD}[INFO]${RESET}  $*"; }
success() { echo -e "${GREEN}${BOLD}[  OK]${RESET}  $*"; }
warn()    { echo -e "${YELLOW}${BOLD}[WARN]${RESET}  $*"; }
error()   { echo -e "${RED}${BOLD}[FAIL]${RESET}  $*"; exit 1; }
step()    { echo -e "\n${MAGENTA}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
            echo -e "${MAGENTA}${BOLD}  $*${RESET}"
            echo -e "${MAGENTA}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"; }
ask()     { echo -e "${YELLOW}${BOLD}[ASK ]${RESET}  $*"; }
divider() { echo -e "${DIM}────────────────────────────────────────────────${RESET}"; }

spinner() {
    local pid=$1 msg=$2 spin='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏' i=0
    while kill -0 "$pid" 2>/dev/null; do
        i=$(( (i+1) % 10 ))
        printf "\r${CYAN}  ${spin:$i:1}  ${msg}...${RESET}"
        sleep 0.1
    done
    printf "\r${GREEN}  ✔  ${msg} — Done!${RESET}\n"
}

run_spin() {
    local msg="$1"; shift
    "$@" &>/tmp/stack_install.log &
    spinner $! "$msg"
}

check_service() {
    systemctl is-active --quiet "$1" \
        && success "$2 is running ✔" \
        || warn "$2 NOT running — journalctl -u $1 -n 20"
}

confirm() {
    while true; do
        ask "$1 ${DIM}[y/n]${RESET}"; read -r yn
        case "$yn" in [Yy]*) return 0;; [Nn]*) return 1;; *) echo "  y or n please.";; esac
    done
}

pick_one() {
    local prompt="$1"; shift; local opts=("$@")
    ask "$prompt"
    for i in "${!opts[@]}"; do echo -e "  ${BOLD}$((i+1)))${RESET} ${opts[$i]}"; done
    while true; do
        read -rp "  Enter number [1-${#opts[@]}]: " c
        [[ "$c" =~ ^[0-9]+$ ]] && (( c>=1 && c<=${#opts[@]} )) && { PICK="${opts[$((c-1))]}"; return; }
        echo "  Invalid — try again."
    done
}

[[ "$EUID" -ne 0 ]] && error "Run as root:  sudo bash $0"

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
echo -e "${DIM}  Interactive Stack Installer  ·  AlmaLinux / RHEL / Rocky  ·  v3.0${RESET}"
divider; echo ""

# ════════════════════════════════════════════════════════════
#  SECTION 0 — OS Detection & Confirmation
# ════════════════════════════════════════════════════════════
step "OS DETECTION"

SUPPORTED_OS=(
    "AlmaLinux 8"
    "AlmaLinux 9"
    "AlmaLinux 10"
    "Rocky Linux 8"
    "Rocky Linux 9"
    "RHEL 8"
    "RHEL 9"
    "RHEL 10"
)

# Auto-detect
DETECTED_NAME="Unknown"
DETECTED_VER="0"
DETECTED_ID="unknown"

if [[ -f /etc/os-release ]]; then
    source /etc/os-release
    DETECTED_NAME="${PRETTY_NAME:-$NAME}"
    DETECTED_VER="${VERSION_ID%%.*}"   # major version only: 8, 9, 10
    DETECTED_ID="${ID:-unknown}"
fi

info "Auto-detected: ${BOLD}${DETECTED_NAME}${RESET}"
echo ""

if confirm "Is this correct?"; then
    OS_ID="$DETECTED_ID"
    OS_VER="$DETECTED_VER"
    OS_NAME="$DETECTED_NAME"
else
    echo ""
    pick_one "Select your OS + version:" "${SUPPORTED_OS[@]}"
    OS_NAME="$PICK"
    case "$OS_NAME" in
        "AlmaLinux 8")    OS_ID="almalinux"; OS_VER="8"  ;;
        "AlmaLinux 9")    OS_ID="almalinux"; OS_VER="9"  ;;
        "AlmaLinux 10")   OS_ID="almalinux"; OS_VER="10" ;;
        "Rocky Linux 8")  OS_ID="rocky";     OS_VER="8"  ;;
        "Rocky Linux 9")  OS_ID="rocky";     OS_VER="9"  ;;
        "RHEL 8")         OS_ID="rhel";      OS_VER="8"  ;;
        "RHEL 9")         OS_ID="rhel";      OS_VER="9"  ;;
        "RHEL 10")        OS_ID="rhel";      OS_VER="10" ;;
    esac
fi

# Validate family
case "$OS_ID" in
    almalinux|rocky|rhel|centos) : ;;
    *) error "Unsupported OS: $OS_ID — Use the Ubuntu/Debian script instead." ;;
esac

success "Proceeding with: ${BOLD}${OS_NAME}${RESET}  (Major version: ${OS_VER})"

# Remi repo base URL differs per major version
case "$OS_VER" in
    8)  REMI_RPM="https://rpms.remirepo.net/enterprise/remi-release-8.rpm" ;;
    9)  REMI_RPM="https://rpms.remirepo.net/enterprise/remi-release-9.rpm" ;;
    10) REMI_RPM="https://rpms.remirepo.net/enterprise/remi-release-10.rpm" ;;
    *)  REMI_RPM="https://rpms.remirepo.net/enterprise/remi-release-${OS_VER}.rpm" ;;
esac

# MySQL repo differs per major version
case "$OS_VER" in
    8)  MYSQL84_RPM="https://repo.mysql.com/mysql84-community-release-el8.rpm"
        MYSQL80_RPM="https://repo.mysql.com/mysql80-community-release-el8-1.noarch.rpm" ;;
    9)  MYSQL84_RPM="https://repo.mysql.com/mysql84-community-release-el9.rpm"
        MYSQL80_RPM="https://repo.mysql.com/mysql80-community-release-el9-1.noarch.rpm" ;;
    10) MYSQL84_RPM="https://repo.mysql.com/mysql84-community-release-el10.rpm"
        MYSQL80_RPM="https://repo.mysql.com/mysql80-community-release-el10.rpm" ;;
    *)  MYSQL84_RPM="https://repo.mysql.com/mysql84-community-release-el${OS_VER}.rpm"
        MYSQL80_RPM="https://repo.mysql.com/mysql80-community-release-el${OS_VER}-1.noarch.rpm" ;;
esac

# ════════════════════════════════════════════════════════════
#  SECTION 1 — Pre-flight
# ════════════════════════════════════════════════════════════
step "PRE-FLIGHT CHECKS"

RAM_MB=$(free -m | awk '/^Mem:/{print $2}')
DISK_FREE=$(df -BG / | awk 'NR==2{gsub("G",""); print $4}')
info "RAM      : ${RAM_MB} MB"
info "Free disk: ${DISK_FREE}G"
(( RAM_MB  < 1024 )) && warn "Less than 1 GB RAM — some services may be slow."
(( DISK_FREE < 10 )) && warn "Less than 10 GB free — consider cleanup."

curl -s --max-time 5 https://google.com &>/dev/null \
    && success "Internet OK" \
    || error "No internet — cannot reach repositories."

confirm "Pre-flight OK. Continue?" || exit 0

# ════════════════════════════════════════════════════════════
#  SECTION 2 — System Update & Base Tools
# ════════════════════════════════════════════════════════════
step "STEP 1 — System Update & Base Tools"

if confirm "Update all system packages now? (Recommended)"; then
    run_spin "Updating system" dnf update -y
    success "System updated"
fi

run_spin "Installing base tools" dnf install -y \
    wget curl vim nano git zip unzip tar \
    net-tools bind-utils lsof htop tree firewalld

systemctl enable --now firewalld &>/dev/null
success "Firewalld enabled"

# ════════════════════════════════════════════════════════════
#  SECTION 3 — Web Server
# ════════════════════════════════════════════════════════════
step "STEP 2 — Web Server"

pick_one "Which web server?" \
    "Apache (httpd)" \
    "Nginx" \
    "Both Apache + Nginx (Apache:80, Nginx:8080)"
WEB_SERVER="$PICK"

install_apache() {
    run_spin "Installing Apache" dnf install -y httpd
    systemctl enable --now httpd
    firewall-cmd --permanent --add-service=http  &>/dev/null
    firewall-cmd --permanent --add-service=https &>/dev/null
    firewall-cmd --reload &>/dev/null
    check_service httpd "Apache"
}
install_nginx() {
    run_spin "Installing Nginx" dnf install -y nginx
    systemctl enable --now nginx
    firewall-cmd --permanent --add-service=http  &>/dev/null
    firewall-cmd --permanent --add-service=https &>/dev/null
    firewall-cmd --reload &>/dev/null
    check_service nginx "Nginx"
}

case "$WEB_SERVER" in
    "Apache (httpd)")
        install_apache ;;
    "Nginx")
        install_nginx ;;
    "Both Apache + Nginx (Apache:80, Nginx:8080)")
        install_apache
        run_spin "Installing Nginx" dnf install -y nginx
        sed -i 's/listen\s*80;/listen 8080;/g'          /etc/nginx/nginx.conf 2>/dev/null || true
        sed -i 's/listen\s*\[::\]:80/listen [::]:8080/g' /etc/nginx/nginx.conf 2>/dev/null || true
        systemctl enable --now nginx
        firewall-cmd --permanent --add-port=8080/tcp &>/dev/null
        firewall-cmd --reload &>/dev/null
        check_service nginx "Nginx (port 8080)"
        ;;
esac

# ════════════════════════════════════════════════════════════
#  SECTION 4 — PHP
# ════════════════════════════════════════════════════════════
step "STEP 3 — PHP"

if confirm "Install PHP?"; then
    rpm -q remi-release &>/dev/null \
        || run_spin "Adding Remi repo" dnf install -y "$REMI_RPM"

    pick_one "Select default PHP version:" \
        "PHP 8.4 (Latest — Recommended)" \
        "PHP 8.3" \
        "PHP 8.2" \
        "PHP 8.1" \
        "PHP 8.0" \
        "PHP 7.4"
    case "$PICK" in
        *8.4*) PHP_VER="8.4"; PHP_MOD="remi-8.4" ;;
        *8.3*) PHP_VER="8.3"; PHP_MOD="remi-8.3" ;;
        *8.2*) PHP_VER="8.2"; PHP_MOD="remi-8.2" ;;
        *8.1*) PHP_VER="8.1"; PHP_MOD="remi-8.1" ;;
        *8.0*) PHP_VER="8.0"; PHP_MOD="remi-8.0" ;;
        *7.4*) PHP_VER="7.4"; PHP_MOD="remi-7.4" ;;
    esac

    dnf module reset php -y &>/dev/null
    dnf module enable php:${PHP_MOD} -y &>/dev/null
    run_spin "Installing PHP ${PHP_VER}" dnf --disableexcludes=all install -y \
        php php-cli php-common php-fpm \
        php-mysqlnd php-gd php-mbstring php-xml \
        php-opcache php-zip php-curl php-intl php-sodium php-pdo
    systemctl enable --now php-fpm
    check_service php-fpm "PHP-FPM ${PHP_VER}"

    # PHP security tweaks
    PHP_INI=$(php --ini 2>/dev/null | grep "Loaded Configuration" | awk '{print $NF}')
    if [[ -f "$PHP_INI" ]]; then
        sed -i 's/^expose_php = On/expose_php = Off/'     "$PHP_INI"
        sed -i 's/^display_errors = On/display_errors = Off/' "$PHP_INI"
        success "PHP hardened (expose_php off, display_errors off)"
    fi

    # Multi-version
    echo ""
    if confirm "Install additional PHP versions? (multi-client support)"; then
        ALL_VERS=(7.4 8.0 8.1 8.2 8.3 8.4 8.5)
        for V in "${ALL_VERS[@]}"; do
            [[ "$V" == "$PHP_VER" ]] && continue
            VN="${V//./}"   # 7.4 → 74
            if confirm "  Install PHP ${V}?"; then
                run_spin "Installing PHP ${V}" dnf --disableexcludes=all install -y \
                    php${VN}-php php${VN}-php-cli php${VN}-php-fpm \
                    php${VN}-php-mysqlnd php${VN}-php-mbstring \
                    php${VN}-php-xml php${VN}-php-gd php${VN}-php-zip php${VN}-php-curl
                systemctl enable --now php${VN}-php-fpm
                check_service php${VN}-php-fpm "PHP-FPM ${V}"
            fi
        done
    fi
fi

# ════════════════════════════════════════════════════════════
#  SECTION 5 — MySQL / MariaDB
# ════════════════════════════════════════════════════════════
step "STEP 4 — MySQL / MariaDB"

if confirm "Install MySQL or MariaDB?"; then
    pick_one "Select database server:" \
        "MySQL 8.4 LTS (Recommended)" \
        "MySQL 8.0" \
        "MariaDB 10.11 LTS" \
        "MariaDB 11.x (Latest)"
    DB_CHOICE="$PICK"

    case "$DB_CHOICE" in
        "MySQL 8.4 LTS (Recommended)")
            run_spin "Adding MySQL 8.4 repo" dnf install -y "$MYSQL84_RPM"
            dnf config-manager --disable "mysql-9*" &>/dev/null || true
            dnf config-manager --enable  mysql-8.4-lts-community \
                                          mysql-tools-8.4-lts-community &>/dev/null || true
            run_spin "Installing MySQL 8.4" dnf install -y mysql-community-server \
                --exclude='mariadb*' --nogpgcheck
            ;;
        "MySQL 8.0")
            run_spin "Adding MySQL 8.0 repo" dnf install -y "$MYSQL80_RPM"
            run_spin "Installing MySQL 8.0" dnf install -y mysql-community-server \
                --exclude='mariadb*' --nogpgcheck
            ;;
        "MariaDB 10.11 LTS")
            cat > /etc/yum.repos.d/mariadb.repo <<REPO
[mariadb]
name=MariaDB 10.11
baseurl=https://downloads.mariadb.com/MariaDB/mariadb-10.11/yum/rhel/\$releasever/\$basearch
gpgkey=https://downloads.mariadb.com/MariaDB/RPM-GPG-KEY-MariaDB
gpgcheck=1
REPO
            run_spin "Installing MariaDB 10.11" dnf install -y MariaDB-server MariaDB-client
            ;;
        "MariaDB 11.x (Latest)")
            cat > /etc/yum.repos.d/mariadb.repo <<REPO
[mariadb]
name=MariaDB 11
baseurl=https://downloads.mariadb.com/MariaDB/mariadb-11/yum/rhel/\$releasever/\$basearch
gpgkey=https://downloads.mariadb.com/MariaDB/RPM-GPG-KEY-MariaDB
gpgcheck=1
REPO
            run_spin "Installing MariaDB 11" dnf install -y MariaDB-server MariaDB-client
            ;;
    esac

    if [[ "$DB_CHOICE" == *"MariaDB"* ]]; then
        systemctl enable --now mariadb
        check_service mariadb "MariaDB"
        warn "Run mysql_secure_installation to set root password"
    else
        systemctl enable --now mysqld
        check_service mysqld "MySQL"
        TEMP_PW=$(grep 'temporary password' /var/log/mysqld.log 2>/dev/null | awk '{print $NF}' | tail -1)
        [[ -n "$TEMP_PW" ]] && {
            warn "MySQL temp root password: ${BOLD}${TEMP_PW}${RESET}"
            echo "MYSQL_TEMP_PASSWORD=${TEMP_PW}" >> /root/stack-credentials.txt
            warn "Saved to /root/stack-credentials.txt — change it immediately!"
        }
    fi
fi

# ════════════════════════════════════════════════════════════
#  SECTION 6 — MongoDB
# ════════════════════════════════════════════════════════════
step "STEP 5 — MongoDB"

if confirm "Install MongoDB?"; then
    pick_one "Select MongoDB version:" \
        "MongoDB 8.0 (Latest Stable)" \
        "MongoDB 7.0 (LTS)"
    MONGO_NUM=$(echo "$PICK" | grep -oP '\d+\.\d+')

    cat > /etc/yum.repos.d/mongodb-org-${MONGO_NUM}.repo <<REPO
[mongodb-org-${MONGO_NUM}]
name=MongoDB ${MONGO_NUM} Repository
baseurl=https://repo.mongodb.org/yum/redhat/${OS_VER}/mongodb-org/${MONGO_NUM}/x86_64/
gpgcheck=1
enabled=1
gpgkey=https://pgp.mongodb.com/server-${MONGO_NUM}.asc
REPO

    run_spin "Installing MongoDB ${MONGO_NUM}" dnf install -y mongodb-org

    ask "MongoDB default port 27017 — enter custom port (recommended for security)"
    read -rp "  Custom port [default: 35001]: " MONGO_PORT
    MONGO_PORT="${MONGO_PORT:-35001}"
    sed -i "s/port: 27017/port: ${MONGO_PORT}/" /etc/mongod.conf

    systemctl enable --now mongod
    check_service mongod "MongoDB"
    firewall-cmd --permanent --add-port=${MONGO_PORT}/tcp &>/dev/null
    firewall-cmd --reload &>/dev/null
    echo "MONGODB_PORT=${MONGO_PORT}" >> /root/stack-credentials.txt
    success "MongoDB on port ${MONGO_PORT} (localhost only)"
    warn "Create admin user BEFORE enabling auth — see docs"
fi

# ════════════════════════════════════════════════════════════
#  SECTION 7 — PostgreSQL
# ════════════════════════════════════════════════════════════
step "STEP 6 — PostgreSQL"

if confirm "Install PostgreSQL?"; then
    pick_one "Select PostgreSQL version:" \
        "PostgreSQL 18 (Latest)" \
        "PostgreSQL 17" \
        "PostgreSQL 16 (LTS)" \
        "PostgreSQL 15" \
        "PostgreSQL 14"
    PG_NUM=$(echo "$PICK" | grep -oP '\d+' | head -1)

    run_spin "Installing PostgreSQL ${PG_NUM}" dnf install -y \
        postgresql${PG_NUM}-server postgresql${PG_NUM}
    /usr/pgsql-${PG_NUM}/bin/postgresql-${PG_NUM}-setup initdb
    systemctl enable --now postgresql-${PG_NUM}
    check_service postgresql-${PG_NUM} "PostgreSQL ${PG_NUM}"
    firewall-cmd --permanent --add-port=5432/tcp &>/dev/null
    firewall-cmd --reload &>/dev/null
    warn "Set password: su - postgres && psql -c \"ALTER USER postgres PASSWORD 'PASS';\""
fi

# ════════════════════════════════════════════════════════════
#  SECTION 8 — SSL (Let's Encrypt — always installed)
# ════════════════════════════════════════════════════════════
step "STEP 7 — SSL via Let's Encrypt (Certbot)"

info "Installing Certbot for Let's Encrypt SSL..."
run_spin "Installing Certbot" dnf install -y certbot python3-certbot-apache python3-certbot-nginx
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

declare -A SVCS=(
    [httpd]="Apache"
    [nginx]="Nginx"
    [php-fpm]="PHP-FPM (default)"
    [mysqld]="MySQL"
    [mariadb]="MariaDB"
    [mongod]="MongoDB"
    [postgresql-14]="PostgreSQL 14"
    [postgresql-15]="PostgreSQL 15"
    [postgresql-16]="PostgreSQL 16"
    [postgresql-17]="PostgreSQL 17"
    [postgresql-18]="PostgreSQL 18"
)
for svc in "${!SVCS[@]}"; do
    systemctl list-units --full -all 2>/dev/null | grep -q "${svc}.service" || continue
    if systemctl is-active --quiet "$svc" 2>/dev/null; then
        echo -e "  ${GREEN}✔${RESET}  ${SVCS[$svc]}"
    else
        echo -e "  ${RED}✘${RESET}  ${SVCS[$svc]} ${DIM}(installed but not active)${RESET}"
    fi
done

divider
echo -e "\n${BOLD}  Listening Ports:${RESET}"
ss -tlnp | grep -E ':80 |:443 |:3306 |:5432 |:8080 |:27017 |:35001 ' \
    | awk '{print "  " $4}' | sort -u

divider
echo -e "\n${BOLD}  Installed Versions:${RESET}"
command -v httpd  &>/dev/null && echo -e "  Apache   : $(httpd -v 2>&1 | head -1)"
command -v nginx  &>/dev/null && echo -e "  Nginx    : $(nginx -v 2>&1)"
command -v php    &>/dev/null && echo -e "  PHP      : $(php -r 'echo PHP_VERSION;')"
command -v mysql  &>/dev/null && echo -e "  MySQL    : $(mysql --version 2>&1)"
command -v psql   &>/dev/null && echo -e "  Postgres : $(psql --version 2>&1)"
command -v mongod &>/dev/null && echo -e "  MongoDB  : $(mongod --version 2>&1 | head -1)"
command -v certbot &>/dev/null && echo -e "  Certbot  : $(certbot --version 2>&1)"

echo ""
echo -e "${GREEN}${BOLD}"
cat << 'EOF'
  ╔══════════════════════════════════════════════════════╗
  ║   ✅  STACK INSTALLATION COMPLETE — HAVE FUN!       ║
  ╚══════════════════════════════════════════════════════╝
EOF
echo -e "${RESET}"
echo -e "${DIM}  Credentials : /root/stack-credentials.txt${RESET}"
echo -e "${DIM}  Install log : /tmp/stack_install.log${RESET}"
echo -e "${DIM}  Next steps  : Set DB passwords · Configure vhosts · Run certbot${RESET}"
echo ""
