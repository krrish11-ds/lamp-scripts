#!/bin/bash
# ============================================================
#  Interactive LAMP / LEMP Stack Installer
#  OS      : Ubuntu 20.04 / 22.04 / 24.04 / Debian 11 / 12
#  Version : 3.1
# ============================================================

# Errors handled manually — no set -e so script never auto-exits
set -uo pipefail
export DEBIAN_FRONTEND=noninteractive

# ── Colors ──────────────────────────────────────────────────
RED='\033[0;31m';  GREEN='\033[0;32m';  YELLOW='\033[1;33m'
CYAN='\033[0;36m'; MAGENTA='\033[0;35m'
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
    local logfile="/tmp/stack_install.log"

    # Run in subshell background so parent shell is not affected by exit codes
    (DEBIAN_FRONTEND=noninteractive "$@" >> "$logfile" 2>&1) &
    local pid=$!

    # Spinner while running
    local spin='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏' i=0
    while kill -0 "$pid" 2>/dev/null; do
        i=$(( (i+1) % 10 ))
        printf "\r${CYAN}  ${spin:$i:1}  ${msg}...${RESET}"
        sleep 0.1
    done

    # Collect exit code safely
    local exit_code=0
    wait "$pid" 2>/dev/null || exit_code=$?

    if [[ $exit_code -ne 0 ]]; then
        printf "\r${RED}${BOLD}  ✘  ${msg} — FAILED (exit ${exit_code})${RESET}\n"
        echo -e "${RED}  ── Error output ─────────────────────────────${RESET}"
        grep -v "^$" "$logfile" | tail -20 | while IFS= read -r line; do
            echo -e "  ${RED}${line}${RESET}"
        done
        echo -e "${RED}  ─────────────────────────────────────────────${RESET}"
        echo -e "  ${DIM}Full log: cat $logfile${RESET}"
        > "$logfile"
        return 1
    else
        printf "\r${GREEN}  ✔  ${msg} — Done!${RESET}\n"
        # Show real warnings only (suppress apt noise)
        local warns
        warns=$(grep -iE "^(W:|E:|error|warning|failed)" "$logfile"             | grep -viE "NOTICE:|Not enabling|To enable|You are seeing|a2enmod|a2enconf"             | tail -10) || true
        if [[ -n "$warns" ]]; then
            echo -e "${YELLOW}  ── Warnings ──────────────────────────────────${RESET}"
            while IFS= read -r line; do
                echo -e "  ${YELLOW}${line}${RESET}"
            done <<< "$warns"
            echo -e "${YELLOW}  ──────────────────────────────────────────────${RESET}"
        fi
        > "$logfile"
    fi
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

# ── prompt_password: asks twice, validates match, stores in $PROMPT_PASSWORD ──
prompt_password() {
    local label="$1"
    while true; do
        read -rsp "  Enter password for ${label}: " p1; echo
        if [[ -z "$p1" ]]; then
            echo -e "  ${RED}Password cannot be empty.${RESET}"; continue
        fi
        read -rsp "  Confirm password: " p2; echo
        if [[ "$p1" != "$p2" ]]; then
            echo -e "  ${RED}Passwords do not match — try again.${RESET}"; continue
        fi
        PROMPT_PASSWORD="$p1"
        return
    done
}

# ── save_credential: appends "label: value" to the credentials file ──
save_credential() {
    touch /root/stack-credentials.txt && chmod 600 /root/stack-credentials.txt
    echo "$1: $2" >> /root/stack-credentials.txt
}

# ── pick_one: single numbered choice ─────────────────────────
pick_one() {
    local prompt="$1"; shift; local opts=("$@")
    local n=${#opts[@]}
    ask "$prompt"
    for i in "${!opts[@]}"; do
        echo -e "  ${BOLD}$((i+1)))${RESET} ${opts[$i]}"
    done
    echo -e "  ${DIM}Enter ONE number (e.g. 3)${RESET}"
    while true; do
        read -rp "  Your choice [1-${n}]: " raw
        # trim leading/trailing spaces
        c="$(echo "$raw" | tr -d '[:space:]')"
        # reject empty
        if [[ -z "$c" ]]; then
            echo -e "  ${RED}Please enter a number.${RESET}"; continue
        fi
        # reject if more than one token was typed
        word_count=$(echo "$raw" | wc -w)
        if (( word_count > 1 )); then
            echo -e "  ${RED}Please enter only ONE number — this field is single-select.${RESET}"
            echo -e "  ${DIM}(For multi-select questions a separate prompt will appear)${RESET}"
            continue
        fi
        # validate range
        if [[ "$c" =~ ^[0-9]+$ ]] && (( c>=1 && c<=n )); then
            PICK="${opts[$((c-1))]}"; return
        fi
        echo -e "  ${RED}Invalid${RESET} — enter a number between 1 and ${n}."
    done
}

# ── pick_multi: comma-separated OR space-separated OR ranges ──
# Usage: pick_multi "Prompt" opt1 opt2 opt3 ...
# Result stored in global array PICKS=()
pick_multi() {
    local prompt="$1"; shift
    local opts=("$@")
    local n=${#opts[@]}
    PICKS=()

    ask "$prompt"
    for i in "${!opts[@]}"; do
        echo -e "  ${BOLD}$((i+1)))${RESET} ${opts[$i]}"
    done
    echo -e "  ${DIM}Enter numbers separated by spaces or commas (e.g.  1 3 5  or  1,3,5  or  all)${RESET}"

    while true; do
        read -rp "  Your selection: " raw
        [[ -z "$raw" ]] && { echo "  Please enter at least one number."; continue; }

        # 'all' shortcut
        if [[ "${raw,,}" == "all" ]]; then
            PICKS=("${opts[@]}")
            echo -e "  ${DIM}Selected (ALL):${RESET} ${PICKS[*]}"
            confirm "  Confirm — install ALL ${n} listed versions?" && return
            continue
        fi

        # normalize: replace commas with spaces
        local normalized="${raw//,/ }"
        local valid=true
        local selected=()

        for token in $normalized; do
            if [[ "$token" =~ ^[0-9]+$ ]] && (( token>=1 && token<=n )); then
                selected+=("${opts[$((token-1))]}")
            else
                echo -e "  ${RED}Invalid value '${token}'${RESET} — must be a number between 1 and ${n}."
                valid=false
                break
            fi
        done

        $valid && {
            PICKS=("${selected[@]}")
            echo -e "  ${DIM}Selected:${RESET} ${PICKS[*]}"
            confirm "  Confirm this selection?" && return
            continue
        }
    done
}

[[ "$EUID" -ne 0 ]] && error "Run as root:  sudo bash $0"

# ── Banner ───────────────────────────────────────────────────
clear
echo -e "\033[0;34m\033[1m"
cat << 'EOF'
  ██╗      █████╗ ███╗   ███╗██████╗     ██╗      ███████╗███╗   ███╗██████╗
  ██║     ██╔══██╗████╗ ████║██╔══██╗    ██║      ██╔════╝████╗ ████║██╔══██╗
  ██║     ███████║██╔████╔██║██████╔╝    ██║      █████╗  ██╔████╔██║██████╔╝
  ██║     ██╔══██║██║╚██╔╝██║██╔═══╝     ██║      ██╔══╝  ██║╚██╔╝██║██╔═══╝
  ███████╗██║  ██║██║ ╚═╝ ██║██║         ███████╗ ███████╗██║ ╚═╝ ██║██║
  ╚══════╝╚═╝  ╚═╝╚═╝     ╚═╝╚═╝         ╚══════╝ ╚══════╝╚═╝     ╚═╝╚═╝
EOF
echo -e "${RESET}"
echo -e "${DIM}  Interactive Stack Installer  ·  Ubuntu / Debian  ·  v3.1${RESET}"
divider; echo ""

# ════════════════════════════════════════════════════════════
#  SECTION 0 — OS Detection & Version Confirmation
# ════════════════════════════════════════════════════════════
step "OS DETECTION"

SUPPORTED_OS=(
    "Ubuntu 20.04 (focal)"
    "Ubuntu 22.04 (jammy)"
    "Ubuntu 24.04 (noble)"
    "Debian 11 (bullseye)"
    "Debian 12 (bookworm)"
)

DETECTED_NAME="Unknown"
DETECTED_CODENAME="unknown"
DETECTED_ID="unknown"

if [[ -f /etc/os-release ]]; then
    source /etc/os-release
    DETECTED_NAME="${PRETTY_NAME:-$NAME}"
    DETECTED_CODENAME="${VERSION_CODENAME:-unknown}"
    DETECTED_ID="${ID:-unknown}"
fi

info "Auto-detected: ${BOLD}${DETECTED_NAME}${RESET}"
echo ""

if confirm "Is this OS detection correct?"; then
    OS_ID="$DETECTED_ID"
    OS_CODENAME="$DETECTED_CODENAME"
    OS_NAME="$DETECTED_NAME"
else
    echo ""
    pick_one "Select your OS + version:" "${SUPPORTED_OS[@]}"
    OS_NAME="$PICK"
    case "$OS_NAME" in
        *"Ubuntu 20.04"*) OS_ID="ubuntu"; OS_CODENAME="focal"     ;;
        *"Ubuntu 22.04"*) OS_ID="ubuntu"; OS_CODENAME="jammy"     ;;
        *"Ubuntu 24.04"*) OS_ID="ubuntu"; OS_CODENAME="noble"     ;;
        *"Debian 11"*)    OS_ID="debian"; OS_CODENAME="bullseye"  ;;
        *"Debian 12"*)    OS_ID="debian"; OS_CODENAME="bookworm"  ;;
    esac
fi

case "$OS_ID" in
    ubuntu|debian) : ;;
    *) error "Unsupported OS: $OS_ID — Use the AlmaLinux script for RHEL-based systems." ;;
esac

success "Proceeding with: ${BOLD}${OS_NAME}${RESET}  (codename: ${OS_CODENAME})"

# ════════════════════════════════════════════════════════════
#  SECTION 1 — Pre-flight
# ════════════════════════════════════════════════════════════
step "PRE-FLIGHT CHECKS"

RAM_MB=$(free -m | awk '/^Mem:/{print $2}')
DISK_FREE=$(df -BG / | awk 'NR==2{gsub("G",""); print $4}')
info "RAM      : ${RAM_MB} MB"
info "Free disk: ${DISK_FREE}G"
(( RAM_MB  < 1024 )) && warn "Less than 1 GB RAM detected."
(( DISK_FREE < 10 )) && warn "Less than 10 GB free disk space."

curl -s --max-time 5 https://google.com &>/dev/null \
    && success "Internet OK" \
    || error "No internet — cannot reach repositories."

confirm "Pre-flight OK. Continue?" || exit 0

# ════════════════════════════════════════════════════════════
#  SECTION 2 — System Update
# ════════════════════════════════════════════════════════════
step "STEP 1 — System Update & Base Tools"

if confirm "Update all system packages now? (Recommended)"; then
    run_spin "Updating package lists" apt-get update -qq
    run_spin "Upgrading packages" apt-get upgrade -y -qq \
        -o Dpkg::Options::="--force-confdef" \
        -o Dpkg::Options::="--force-confold"
    success "System updated"
fi

run_spin "Installing base tools" apt-get install -y -qq \
    wget curl vim nano git zip unzip tar \
    net-tools dnsutils lsof htop tree \
    software-properties-common gnupg2 \
    ca-certificates lsb-release apt-transport-https

# NOTE: UFW intentionally NOT installed/enabled — firewall management
# is left to the user / infra layer, per request.

# ════════════════════════════════════════════════════════════
#  SECTION 3 — Web Server
# ════════════════════════════════════════════════════════════
step "STEP 2 — Web Server"

pick_one "Which web server do you want?" \
    "Apache2" \
    "Nginx" \
    "Both (Apache2 on 80/443, Nginx on 8080)"
WEB_SERVER="$PICK"

install_apache2() {
    run_spin "Installing Apache2" apt-get install -y -qq apache2
    systemctl enable --now apache2
    a2enmod rewrite headers ssl &>/dev/null
    systemctl restart apache2
    check_service apache2 "Apache2"
}
install_nginx() {
    run_spin "Installing Nginx" apt-get install -y -qq nginx
    systemctl enable --now nginx
    check_service nginx "Nginx"
}

case "$WEB_SERVER" in
    "Apache2") install_apache2 ;;
    "Nginx")   install_nginx   ;;
    "Both (Apache2 on 80/443, Nginx on 8080)")
        install_apache2
        run_spin "Installing Nginx" apt-get install -y -qq nginx
        # Move Nginx to port 8080
        NGINX_DEFAULT="/etc/nginx/sites-available/default"
        [[ -f "$NGINX_DEFAULT" ]] && {
            sed -i 's/listen 80 default_server;/listen 8080 default_server;/'     "$NGINX_DEFAULT"
            sed -i 's/listen \[::\]:80 default_server;/listen [::]:8080 default_server;/' "$NGINX_DEFAULT"
        }
        systemctl enable --now nginx
        nginx -t &>/dev/null && systemctl restart nginx
        check_service nginx "Nginx (port 8080)"
        ;;
esac

# ════════════════════════════════════════════════════════════
#  SECTION 4 — PHP
# ════════════════════════════════════════════════════════════
step "STEP 3 — PHP"

# All available PHP versions across 7.x and 8.x
ALL_PHP_VERSIONS=(7.0 7.1 7.2 7.3 7.4 8.0 8.1 8.2 8.3 8.4 8.5)

if confirm "Install PHP?"; then

    # Add PPA / repo
    if [[ "$OS_ID" == "ubuntu" ]]; then
        run_spin "Adding ondrej/php PPA" add-apt-repository -y ppa:ondrej/php
    else
        # Debian — use sury repo
        curl -sSL https://packages.sury.org/php/apt.gpg \
            | gpg --dearmor -o /usr/share/keyrings/php-sury.gpg
        echo "deb [signed-by=/usr/share/keyrings/php-sury.gpg] \
https://packages.sury.org/php/ ${OS_CODENAME} main" \
            > /etc/apt/sources.list.d/php-sury.list
    fi
    run_spin "Refreshing package lists" apt-get update -qq

    # ── Pick ALL versions to install (multi-select, supports "all") ──
    echo ""
    pick_multi "Select PHP version(s) to install:" \
        "PHP 7.0" "PHP 7.1" "PHP 7.2" "PHP 7.3" "PHP 7.4" \
        "PHP 8.0" "PHP 8.1" "PHP 8.2" "PHP 8.3" "PHP 8.4" "PHP 8.5 (Latest)"

    SELECTED_PHP_VERSIONS=()
    for p in "${PICKS[@]}"; do
        ver=$(echo "$p" | grep -oP '[\d.]+' | head -1)
        SELECTED_PHP_VERSIONS+=("$ver")
    done

    if [[ ${#SELECTED_PHP_VERSIONS[@]} -eq 0 ]]; then
        warn "No PHP version selected — skipping PHP install."
    fi

    # ── Helper: install one PHP version safely ──
    # Tries each extension individually — skips if not available
    install_php_ext() {
        local pkg="$1"
        # Check if package exists in apt cache before trying to install
        if apt-cache show "$pkg" &>/dev/null 2>&1; then
            DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "$pkg"                 >> /tmp/stack_install.log 2>&1 || true
        fi
        # silently skip if not available — no error
    }

    # ── Helper: build CORE package list (always available) ──
    php_packages() {
        local ver="$1"
        local major="${ver%%.*}"
        local minor="${ver##*.}"

        # Only absolutely core packages that exist for all versions
        local pkgs="php${ver} php${ver}-cli php${ver}-fpm php${ver}-common"
        echo "$pkgs"
    }

    # ── Helper: install optional PHP extensions for a version ──
    # ── Production LAMP/LEMP mandatory extensions only ──
    # sodium/readline removed — not needed for real LAMP/LEMP prod setup
    php_install_extensions() {
        local ver="$1"
        local major="${ver%%.*}"
        local minor="${ver##*.}"

        # Core production extensions — every one of these is needed
        local prod_exts=(
            "php${ver}-mysql"     # Database (MySQL/MariaDB)
            "php${ver}-curl"      # HTTP requests / API calls
            "php${ver}-gd"        # Image processing
            "php${ver}-mbstring"  # UTF-8 / multi-byte string support
            "php${ver}-xml"       # XML, RSS, SOAP, SimpleXML
            "php${ver}-zip"       # File uploads, compression
            "php${ver}-opcache"   # Bytecode cache — performance
            "php${ver}-intl"      # Internationalization
            "php${ver}-bcmath"    # Precise math (payments, finance)
        )

        # Apache mod_php — only when Apache is the web server
        if [[ "$WEB_SERVER" == *"Apache"* ]] || [[ "$WEB_SERVER" == *"Both"* ]]; then
            prod_exts+=("libapache2-mod-php${ver}")
        fi

        local ok=0 skip=0
        for pkg in "${prod_exts[@]}"; do
            # Only install if package actually exists in repo
            if apt-cache show "$pkg" &>/dev/null 2>&1; then
                DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "$pkg"                     >> /tmp/stack_install.log 2>&1 && (( ok++ )) || true
            else
                (( skip++ )) || true
            fi
        done

        [[ $ok   -gt 0 ]] && echo -e "  ${DIM}  ${ok} extensions installed${RESET}"
        [[ $skip -gt 0 ]] && echo -e "  ${DIM}  ${skip} not available for PHP ${ver} (skipped)${RESET}"
    }

    # ── Helper: safe enable + start php-fpm ──
    enable_php_fpm() {
        local ver="$1"
        local svc="php${ver}-fpm"

        # Check if unit file physically exists on disk (more reliable than systemctl list)
        local unit_paths=(
            "/lib/systemd/system/${svc}.service"
            "/usr/lib/systemd/system/${svc}.service"
            "/etc/systemd/system/${svc}.service"
        )
        local unit_found=false
        for path in "${unit_paths[@]}"; do
            [[ -f "$path" ]] && { unit_found=true; break; }
        done

        if ! $unit_found; then
            # Last attempt: force reinstall the fpm package directly (not via run_spin)
            info "Re-attempting php${ver}-fpm package install..."
            apt-get install -y -qq "php${ver}-fpm" >>/tmp/stack_install.log 2>&1
            # Re-check after reinstall
            for path in "${unit_paths[@]}"; do
                [[ -f "$path" ]] && { unit_found=true; break; }
            done
        fi

        if ! $unit_found; then
            warn "php${ver}-fpm.service not found even after reinstall."
            warn "Check log: cat /tmp/stack_install.log"
            return 1
        fi

        # Reload systemd so it sees new unit files
        systemctl daemon-reload &>/dev/null

        # Enable and start
        if systemctl enable --now "$svc" &>/dev/null; then
            check_service "$svc" "PHP-FPM ${ver}"
        else
            warn "PHP-FPM ${ver} failed to start — check: journalctl -u ${svc} -n 20"
        fi
    }

    # ── Install PHP versions (foreground — no background/spinner) ──
    # apt-get MUST complete fully before systemctl runs
    # so we run installs in foreground and show a simple progress line
    install_php_ver() {
        local ver="$1"

        # Step 1: Install core (cli, fpm, common) — must succeed
        local core_pkgs="php${ver} php${ver}-cli php${ver}-fpm php${ver}-common"
        echo -ne "${CYAN}  ⠿  Installing PHP ${ver} (core)...${RESET}"
        > /tmp/stack_install.log

        if DEBIAN_FRONTEND=noninteractive apt-get install -y -qq $core_pkgs                 >> /tmp/stack_install.log 2>&1; then
            echo -e "
${GREEN}  ✔  PHP ${ver} core installed${RESET}                    "
        else
            echo -e "
${RED}  ✘  PHP ${ver} core FAILED${RESET}"
            grep -iE "^(E:|error|failed)" /tmp/stack_install.log | head -5 |                 while IFS= read -r line; do echo -e "  ${RED}${line}${RESET}"; done
            > /tmp/stack_install.log
            return 1
        fi

        # Step 2: Extensions — each tried individually, unavailable ones skipped
        echo -ne "${CYAN}  ⠿  PHP ${ver} extensions...${RESET}"
        > /tmp/stack_install.log
        php_install_extensions "$ver"
        echo -e "
${GREEN}  ✔  PHP ${ver} — extensions done${RESET}              "

        # Show real warnings only
        local warns
        warns=$(grep -iE "^(W:|E:|error|warning|failed)" /tmp/stack_install.log             | grep -viE "NOTICE:|Not enabling|To enable|You are seeing|a2enmod|a2enconf"             | tail -5) || true
        [[ -n "$warns" ]] && echo -e "${YELLOW}${warns}${RESET}"
        > /tmp/stack_install.log

        # Step 3: Enable FPM service
        enable_php_fpm "$ver"
    }

    INSTALLED_PHP_VERSIONS=()
    for ver in "${SELECTED_PHP_VERSIONS[@]}"; do
        if install_php_ver "$ver" ""; then
            INSTALLED_PHP_VERSIONS+=("$ver")
        fi
    done

    if [[ ${#INSTALLED_PHP_VERSIONS[@]} -eq 0 ]]; then
        warn "No PHP version installed successfully — skipping default selection."
    else
        # ── Now that we know what's actually installed, ask which
        #    one should be the DEFAULT (active) version ──
        echo ""
        DEFAULT_OPTS=()
        for ver in "${INSTALLED_PHP_VERSIONS[@]}"; do
            DEFAULT_OPTS+=("PHP ${ver}")
        done
        pick_one "Which installed PHP version should be the DEFAULT (active) version?" "${DEFAULT_OPTS[@]}"
        DEFAULT_PHP=$(echo "$PICK" | grep -oP '[\d.]+' | head -1)
        info "Default PHP set to: ${BOLD}${DEFAULT_PHP}${RESET}"

        # ── Apache + PHP-FPM integration (if Apache installed) ──
        if systemctl is-active --quiet apache2 2>/dev/null; then
            info "Enabling Apache proxy_fcgi for PHP-FPM integration..."
            a2enmod proxy_fcgi setenvif &>/dev/null && systemctl restart apache2 &>/dev/null
            # Enable fpm conf for default PHP version
            if a2enconf "php${DEFAULT_PHP}-fpm" &>/dev/null; then
                systemctl reload apache2 &>/dev/null
                success "Apache configured to use PHP-FPM ${DEFAULT_PHP} via proxy_fcgi"
            fi
        fi

        # ── PHP hardening on default version ──
        PHP_INI="/etc/php/${DEFAULT_PHP}/fpm/php.ini"
        if [[ -f "$PHP_INI" ]]; then
            sed -i 's/^expose_php = On/expose_php = Off/'         "$PHP_INI"
            sed -i 's/^display_errors = On/display_errors = Off/' "$PHP_INI"
            sed -i 's/^allow_url_fopen = On/allow_url_fopen = Off/' "$PHP_INI"
            systemctl restart php${DEFAULT_PHP}-fpm &>/dev/null
            success "PHP ${DEFAULT_PHP} hardened (expose_php off, display_errors off)"
        fi

        # ── Register all installed versions with update-alternatives,
        #    then set the chosen DEFAULT_PHP as the active `php` CLI binary.
        #    (We use --set, not --config, since --config waits on an
        #    interactive prompt and would hang a non-interactive script —
        #    the user already told us their choice via pick_one above.
        #    Run `sudo update-alternatives --config php` anytime afterward
        #    to switch interactively.)
        info "Configuring 'php' CLI alternative..."
        ALT_PRIORITY=10
        for ver in "${INSTALLED_PHP_VERSIONS[@]}"; do
            bin="/usr/bin/php${ver}"
            if [[ -x "$bin" ]]; then
                update-alternatives --install /usr/bin/php php "$bin" "$ALT_PRIORITY" &>/dev/null
                ALT_PRIORITY=$((ALT_PRIORITY+10))
            fi
        done
        update-alternatives --set php "/usr/bin/php${DEFAULT_PHP}" &>/dev/null
        success "Default CLI 'php' -> PHP ${DEFAULT_PHP}  (change later with: sudo update-alternatives --config php)"

        echo ""
        info "Installed PHP versions summary:"
        for ver in "${INSTALLED_PHP_VERSIONS[@]}"; do
            if [[ "$ver" == "$DEFAULT_PHP" ]]; then
                echo -e "  ${GREEN}●${RESET} ${BOLD}${ver}${RESET} (default/active)"
            else
                echo -e "  ${CYAN}●${RESET} ${ver} (additional FPM pool)"
            fi
        done
    fi
fi

# ════════════════════════════════════════════════════════════
#  SECTION 5 — MySQL / MariaDB
# ════════════════════════════════════════════════════════════
step "STEP 4 — MySQL / MariaDB"

if confirm "Install MySQL or MariaDB?"; then
    pick_one "Select database server (one only — MySQL/MariaDB share the same port/service and can't run side by side):" \
        "MySQL 8.4 LTS (Recommended)" \
        "MySQL 8.0" \
        "MySQL 5.7 (Legacy)" \
        "MariaDB 10.11 LTS" \
        "MariaDB 11.x (Latest)"
    DB_CHOICE="$PICK"

    # ── Helper: prompt for a root password and apply it ──
    set_db_root_password() {
        local service="$1" label="$2"
        prompt_password "${label} root"
        local pass1="$PROMPT_PASSWORD"

        if [[ "$service" == "mariadb" ]]; then
            mysql -u root -e \
                "ALTER USER 'root'@'localhost' IDENTIFIED VIA mysql_native_password USING PASSWORD('${pass1}'); FLUSH PRIVILEGES;" \
                2>/tmp/stack_install.log \
                || mysql -u root -e "SET PASSWORD FOR 'root'@'localhost' = PASSWORD('${pass1}'); FLUSH PRIVILEGES;" 2>/tmp/stack_install.log
        else
            mysql -u root -e \
                "ALTER USER 'root'@'localhost' IDENTIFIED WITH caching_sha2_password BY '${pass1}'; FLUSH PRIVILEGES;" \
                2>/tmp/stack_install.log
        fi

        if [[ $? -eq 0 ]]; then
            success "${label} root password set"
            save_credential "${label} root password" "${pass1}"
        else
            warn "Could not set ${label} root password automatically — set it manually:"
            warn "  sudo mysql_secure_installation"
            cat /tmp/stack_install.log 2>/dev/null | tail -5
        fi
        > /tmp/stack_install.log
    }

    # Helper: fix MySQL GPG key (expired key issue on Ubuntu noble)
    fix_mysql_gpg() {
        # Remove broken MySQL repo entry first
        rm -f /etc/apt/sources.list.d/mysql*.list
        # Import fresh GPG key directly from keyserver
        gpg --keyserver keyserver.ubuntu.com             --recv-keys B7B3B788A8D3785C &>/dev/null || true
        gpg --export B7B3B788A8D3785C             | tee /usr/share/keyrings/mysql-archive-keyring.gpg &>/dev/null
    }

    case "$DB_CHOICE" in
        "MySQL 8.4 LTS (Recommended)")
            info "Adding MySQL 8.4 repository..."
            wget -q https://repo.mysql.com/mysql-apt-config_0.8.30-1_all.deb                 -O /tmp/mysql-apt.deb
            DEBIAN_FRONTEND=noninteractive MYSQL_SERVER_DEFAULT="mysql-8.4-lts"                 dpkg -i /tmp/mysql-apt.deb &>/dev/null || true
            fix_mysql_gpg
            # Write clean signed repo entry
            echo "deb [signed-by=/usr/share/keyrings/mysql-archive-keyring.gpg] http://repo.mysql.com/apt/ubuntu ${OS_CODENAME} mysql-8.4-lts"                 > /etc/apt/sources.list.d/mysql-8.4.list
            run_spin "Refreshing apt" apt-get update -qq
            run_spin "Installing MySQL 8.4" apt-get install -y -qq mysql-server
            ;;
        "MySQL 8.0")
            info "Adding MySQL 8.0 repository..."
            wget -q https://repo.mysql.com/mysql-apt-config_0.8.30-1_all.deb                 -O /tmp/mysql-apt.deb
            DEBIAN_FRONTEND=noninteractive dpkg -i /tmp/mysql-apt.deb &>/dev/null || true
            fix_mysql_gpg
            echo "deb [signed-by=/usr/share/keyrings/mysql-archive-keyring.gpg] http://repo.mysql.com/apt/ubuntu ${OS_CODENAME} mysql-8.0"                 > /etc/apt/sources.list.d/mysql-8.0.list
            run_spin "Refreshing apt" apt-get update -qq
            run_spin "Installing MySQL 8.0" apt-get install -y -qq mysql-server
            ;;
        "MySQL 5.7 (Legacy)")
            warn "MySQL 5.7 is EOL — only for legacy compatibility"
            if [[ "$OS_CODENAME" == "focal" ]]; then
                run_spin "Installing MySQL 5.7" apt-get install -y -qq mysql-server-5.7
            else
                warn "MySQL 5.7 not available for ${OS_CODENAME} — installing 8.0 instead"
                fix_mysql_gpg
                run_spin "Refreshing apt" apt-get update -qq
                run_spin "Installing MySQL 8.0 (fallback)" apt-get install -y -qq mysql-server
            fi
            ;;
        "MariaDB 10.11 LTS")
            curl -LsS https://downloads.mariadb.com/MariaDB/mariadb_repo_setup                 | bash -s -- --mariadb-server-version="mariadb-10.11" &>/tmp/stack_install.log
            run_spin "Refreshing apt" apt-get update -qq
            run_spin "Installing MariaDB 10.11" apt-get install -y -qq mariadb-server mariadb-client
            ;;
        "MariaDB 11.x (Latest)")
            curl -LsS https://downloads.mariadb.com/MariaDB/mariadb_repo_setup                 | bash -s -- --mariadb-server-version="mariadb-11" &>/tmp/stack_install.log
            run_spin "Refreshing apt" apt-get update -qq
            run_spin "Installing MariaDB 11" apt-get install -y -qq mariadb-server mariadb-client
            ;;
    esac

    if [[ "$DB_CHOICE" == *"MariaDB"* ]]; then
        systemctl enable --now mariadb
        check_service mariadb "MariaDB"
        set_db_root_password "mariadb" "MariaDB"
    else
        systemctl enable --now mysql
        check_service mysql "MySQL"
        set_db_root_password "mysql" "MySQL"
    fi
fi

# ════════════════════════════════════════════════════════════
#  SECTION 6 — MongoDB
# ════════════════════════════════════════════════════════════
step "STEP 5 — MongoDB"

if confirm "Install MongoDB?"; then
    pick_one "Select MongoDB version (one only — same package/port, can't run multiple majors side by side via apt):" \
        "MongoDB 8.0 (Latest Stable)" \
        "MongoDB 7.0 (LTS)" \
        "MongoDB 6.0"
    MONGO_NUM=$(echo "$PICK" | grep -oP '\d+\.\d+')

    curl -fsSL https://www.mongodb.org/static/pgp/server-${MONGO_NUM}.asc         | gpg --dearmor -o /usr/share/keyrings/mongodb-server.gpg

    # MongoDB repos — noble not yet supported, use jammy
    MONGO_CODENAME="$OS_CODENAME"
    [[ "$OS_CODENAME" == "noble" ]] && MONGO_CODENAME="jammy"

    echo "deb [ arch=amd64,arm64 signed-by=/usr/share/keyrings/mongodb-server.gpg ] https://repo.mongodb.org/apt/ubuntu ${MONGO_CODENAME}/mongodb-org/${MONGO_NUM} multiverse"         > /etc/apt/sources.list.d/mongodb-org-${MONGO_NUM}.list

    run_spin "Refreshing apt" apt-get update -qq
    run_spin "Installing MongoDB ${MONGO_NUM}" apt-get install -y -qq mongodb-org

    # Default port 27017 — bind localhost only (secure by default)
    sed -i "s/bindIp: 127.0.0.1/bindIp: 127.0.0.1/" /etc/mongod.conf

    MONGO_PORT=27017
    if confirm "Use a custom port instead of the default (${MONGO_PORT})?"; then
        while true; do
            read -rp "  Enter custom port for MongoDB: " custom_port
            if [[ "$custom_port" =~ ^[0-9]+$ ]] && (( custom_port >= 1 && custom_port <= 65535 )); then
                MONGO_PORT="$custom_port"
                break
            fi
            echo -e "  ${RED}Invalid port — enter a number between 1 and 65535.${RESET}"
        done
        sed -i "s/^  port: .*/  port: ${MONGO_PORT}/" /etc/mongod.conf
    fi

    systemctl enable --now mongod
    check_service mongod "MongoDB"
    info "MongoDB running on port ${MONGO_PORT} (localhost only — not exposed to internet)"

    if confirm "Create an admin user and enable authentication now?"; then
        read -rp "  Enter admin username [admin]: " mongo_user
        mongo_user="${mongo_user:-admin}"
        prompt_password "MongoDB admin user '${mongo_user}'"
        mongo_pass="$PROMPT_PASSWORD"

        # Create the user BEFORE turning on auth — with auth still off,
        # localhost connections are unauthenticated so this just works.
        MONGO_SHELL="mongosh"
        command -v mongosh &>/dev/null || MONGO_SHELL="mongo"

        if "$MONGO_SHELL" --port "$MONGO_PORT" --quiet --eval \
            "db.getSiblingDB('admin').createUser({user: '${mongo_user}', pwd: '${mongo_pass}', roles: ['root']})" \
            &>/tmp/stack_install.log; then
            success "MongoDB admin user '${mongo_user}' created"

            # Now enable authorization and restart so it takes effect
            if grep -q "^security:" /etc/mongod.conf; then
                sed -i '/^security:/,/^[^ ]/ s/#\?\s*authorization:.*/  authorization: enabled/' /etc/mongod.conf
            else
                printf '\nsecurity:\n  authorization: enabled\n' >> /etc/mongod.conf
            fi
            systemctl restart mongod
            check_service mongod "MongoDB (with auth enabled)"
            save_credential "MongoDB admin user" "${mongo_user}"
            save_credential "MongoDB admin password" "${mongo_pass}"
            info "Connect with: mongosh --port ${MONGO_PORT} -u ${mongo_user} -p --authenticationDatabase admin"
        else
            warn "Could not create MongoDB admin user automatically — auth NOT enabled:"
            cat /tmp/stack_install.log 2>/dev/null | tail -5
        fi
        > /tmp/stack_install.log
    else
        warn "Auth left disabled — anyone with local/network access to port ${MONGO_PORT} can connect without a password."
        warn "Create an admin user BEFORE enabling auth — see MongoDB docs."
    fi
fi

# ════════════════════════════════════════════════════════════
#  SECTION 7 — PostgreSQL
# ════════════════════════════════════════════════════════════
step "STEP 6 — PostgreSQL"

if confirm "Install PostgreSQL?"; then
    pick_multi "Select PostgreSQL version(s) to install (these run as separate clusters, side by side, each on its own port):" \
        "PostgreSQL 18 (Latest)" \
        "PostgreSQL 17" \
        "PostgreSQL 16 (LTS)" \
        "PostgreSQL 15" \
        "PostgreSQL 14" \
        "PostgreSQL 13"

    PG_VERSIONS=()
    for p in "${PICKS[@]}"; do
        v=$(echo "$p" | grep -oP '\d+' | head -1)
        PG_VERSIONS+=("$v")
    done

    curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc \
        | gpg --dearmor -o /usr/share/keyrings/postgresql.gpg
    echo "deb [signed-by=/usr/share/keyrings/postgresql.gpg] \
https://apt.postgresql.org/pub/repos/apt ${OS_CODENAME}-pgdg main" \
        > /etc/apt/sources.list.d/pgdg.list

    # Refresh only pgdg — ignore any unrelated repo errors (e.g. MySQL GPG)
    run_spin "Refreshing apt" apt-get update -qq -o Dir::Etc::sourcelist="sources.list.d/pgdg.list"         -o Dir::Etc::sourceparts="-" -o APT::Get::List-Cleanup="0"

    if confirm "Use custom port(s) instead of the automatic defaults (5432, 5433, ...)?"; then
        USE_CUSTOM_PG_PORT=true
        while true; do
            read -rp "  Enter starting port (subsequent versions get +1 each): " pg_start_port
            if [[ "$pg_start_port" =~ ^[0-9]+$ ]] && (( pg_start_port >= 1 && pg_start_port <= 65535 )); then
                break
            fi
            echo -e "  ${RED}Invalid port — enter a number between 1 and 65535.${RESET}"
        done
    else
        USE_CUSTOM_PG_PORT=false
    fi

    # Install each selected major version. The postgresql-common package
    # auto-creates a separate cluster per version (pg_createcluster) and
    # assigns each one the next free port automatically (5432, 5433, ...)
    # — so multiple major versions genuinely run side by side here.
    INSTALLED_PG_VERSIONS=()
    pg_next_port="${pg_start_port:-5432}"
    for PG_NUM in "${PG_VERSIONS[@]}"; do
        if run_spin "Installing PostgreSQL ${PG_NUM}" apt-get install -y -qq \
            postgresql-${PG_NUM} postgresql-client-${PG_NUM}; then
            INSTALLED_PG_VERSIONS+=("$PG_NUM")
            if $USE_CUSTOM_PG_PORT; then
                pg_conftool "$PG_NUM" main set port "$pg_next_port" &>/dev/null
                systemctl restart "postgresql@${PG_NUM}-main" &>/dev/null
                info "PostgreSQL ${PG_NUM} cluster set to port ${pg_next_port}"
                pg_next_port=$((pg_next_port+1))
            fi
        fi
    done

    systemctl enable --now postgresql
    check_service postgresql "PostgreSQL"

    if command -v pg_lsclusters &>/dev/null; then
        echo ""
        info "PostgreSQL clusters (version, port):"
        pg_lsclusters
    fi

    if [[ ${#INSTALLED_PG_VERSIONS[@]} -gt 0 ]]; then
        if confirm "Set the 'postgres' user password now (same password applied to every installed cluster)?"; then
            prompt_password "PostgreSQL 'postgres' user"
            pg_pass="$PROMPT_PASSWORD"
            for PG_NUM in "${INSTALLED_PG_VERSIONS[@]}"; do
                pg_port=$(pg_lsclusters | awk -v v="$PG_NUM" '$1==v{print $3; exit}')
                pg_port="${pg_port:-5432}"
                if sudo -u postgres psql -p "$pg_port" -c \
                    "ALTER USER postgres PASSWORD '${pg_pass}';" \
                    &>/tmp/stack_install.log; then
                    success "PostgreSQL ${PG_NUM} (port ${pg_port}) — postgres password set"
                else
                    warn "Could not set password for PG ${PG_NUM} (port ${pg_port}) automatically:"
                    cat /tmp/stack_install.log 2>/dev/null | tail -5
                fi
            done
            > /tmp/stack_install.log
            save_credential "PostgreSQL postgres password (all clusters)" "${pg_pass}"
        else
            for PG_NUM in "${INSTALLED_PG_VERSIONS[@]}"; do
                warn "Set password for PG ${PG_NUM} cluster: sudo -u postgres psql -p <port> -c \"ALTER USER postgres PASSWORD 'PASS';\""
            done
        fi
    fi
fi

# ════════════════════════════════════════════════════════════
#  SECTION 8 — Node.js (multi-version via nvm, like PHP)
# ════════════════════════════════════════════════════════════
step "STEP 7 — Node.js"

if confirm "Install Node.js?"; then
    pick_multi "Select Node.js version(s) to install:" \
        "Node 14 (EOL)" \
        "Node 16 (EOL)" \
        "Node 18 (LTS - Maintenance)" \
        "Node 19 (EOL)" \
        "Node 20 (LTS)" \
        "Node 21 (EOL)" \
        "Node 22 (LTS)" \
        "Node 23 (EOL)" \
        "Node 24 (Current)" \
        "Node 25 (Latest)"

    NODE_VERSIONS=()
    for p in "${PICKS[@]}"; do
        v=$(echo "$p" | grep -oP '\d+' | head -1)
        NODE_VERSIONS+=("$v")
    done

    if [[ ${#NODE_VERSIONS[@]} -eq 0 ]]; then
        warn "No Node.js version selected — skipping."
    else
        # System-wide nvm install (not per-user ~/.nvm) so every user/shell
        # — and non-interactive contexts via the symlink below — can see it.
        export NVM_DIR="/usr/local/nvm"
        mkdir -p "$NVM_DIR"
        if [[ ! -s "$NVM_DIR/nvm.sh" ]]; then
            run_spin "Installing nvm" bash -c \
                "curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | NVM_DIR=$NVM_DIR bash"
        fi
        # shellcheck disable=SC1091
        source "$NVM_DIR/nvm.sh"

        # Make nvm available in every login shell
        cat > /etc/profile.d/nvm.sh << EOF
export NVM_DIR="/usr/local/nvm"
[ -s "\$NVM_DIR/nvm.sh" ] && \. "\$NVM_DIR/nvm.sh"
EOF

        INSTALLED_NODE_VERSIONS=()
        for ver in "${NODE_VERSIONS[@]}"; do
            info "Installing Node.js ${ver}..."
            if nvm install "$ver" >> /tmp/stack_install.log 2>&1; then
                INSTALLED_NODE_VERSIONS+=("$ver")
                success "Node.js ${ver} installed"
            else
                warn "Node.js ${ver} install FAILED — see /tmp/stack_install.log"
            fi
        done
        > /tmp/stack_install.log

        if [[ ${#INSTALLED_NODE_VERSIONS[@]} -eq 1 ]]; then
            DEFAULT_NODE="${INSTALLED_NODE_VERSIONS[0]}"
            info "Only one Node.js version installed — setting ${DEFAULT_NODE} as default automatically."
            nvm alias default "$DEFAULT_NODE" &>/dev/null
        elif [[ ${#INSTALLED_NODE_VERSIONS[@]} -gt 1 ]]; then
            echo ""
            DEFAULT_NODE_OPTS=()
            for ver in "${INSTALLED_NODE_VERSIONS[@]}"; do
                DEFAULT_NODE_OPTS+=("Node ${ver}")
            done
            pick_one "Which installed Node.js version should be the DEFAULT?" "${DEFAULT_NODE_OPTS[@]}"
            DEFAULT_NODE=$(echo "$PICK" | grep -oP '\d+' | head -1)
            nvm alias default "$DEFAULT_NODE" &>/dev/null
        fi

        if [[ -n "${DEFAULT_NODE:-}" ]]; then

            # nvm only works in interactive bash shells. For system-wide
            # access (cron, systemd units, other shells), symlink the
            # default version's node/npm/npx into /usr/local/bin.
            NODE_BIN_DIR=$(dirname "$(nvm which "$DEFAULT_NODE")")
            for bin in node npm npx; do
                [[ -x "${NODE_BIN_DIR}/${bin}" ]] && ln -sf "${NODE_BIN_DIR}/${bin}" "/usr/local/bin/${bin}"
            done
            success "Default Node.js -> ${DEFAULT_NODE}  (change later with: nvm alias default <version>)"

            echo ""
            info "Installed Node.js versions summary:"
            for ver in "${INSTALLED_NODE_VERSIONS[@]}"; do
                if [[ "$ver" == "$DEFAULT_NODE" ]]; then
                    echo -e "  ${GREEN}●${RESET} ${BOLD}${ver}${RESET} (default/active)"
                else
                    echo -e "  ${CYAN}●${RESET} ${ver} (installed via nvm)"
                fi
            done
        fi

        # ── PM2 (process manager — useful for Node apps, and for Python
        #    apps too since pm2 can run any interpreter/binary) ──
        if command -v npm &>/dev/null; then
            if confirm "Install PM2 globally (process manager for keeping Node/Python apps running)?"; then
                run_spin "Installing PM2" npm install -g pm2
                if command -v pm2 &>/dev/null; then
                    success "PM2 installed: $(pm2 --version 2>/dev/null)"
                    if confirm "Enable PM2 to auto-start on server reboot?"; then
                        pm2_startup_cmd=$(pm2 startup systemd -u root --hp /root 2>/dev/null | grep -E '^sudo ' | tail -1)
                        [[ -n "$pm2_startup_cmd" ]] && eval "${pm2_startup_cmd#sudo }" &>/dev/null
                        success "PM2 startup hook installed (run 'pm2 save' after starting your apps)"
                    fi
                else
                    warn "PM2 install failed — check: cat /tmp/stack_install.log"
                fi
            fi
        fi
    fi
fi

# ════════════════════════════════════════════════════════════
#  SECTION 9 — Python (multi-version via deadsnakes, like PHP)
# ════════════════════════════════════════════════════════════
step "STEP 8 — Python"

if confirm "Install additional Python version(s)?"; then
    pick_multi "Select Python version(s) to install alongside the system Python:" \
        "Python 3.9" "Python 3.10" "Python 3.11" "Python 3.12" "Python 3.13" "Python 3.14"

    PYTHON_VERSIONS=()
    for p in "${PICKS[@]}"; do
        v=$(echo "$p" | grep -oP '[\d.]+' | head -1)
        PYTHON_VERSIONS+=("$v")
    done

    if [[ ${#PYTHON_VERSIONS[@]} -eq 0 ]]; then
        warn "No Python version selected — skipping."
    else
        run_spin "Adding deadsnakes/ppa" add-apt-repository -y ppa:deadsnakes/ppa
        run_spin "Refreshing apt" apt-get update -qq

        INSTALLED_PYTHON_VERSIONS=()
        for ver in "${PYTHON_VERSIONS[@]}"; do
            if run_spin "Installing Python ${ver}" apt-get install -y -qq \
                "python${ver}" "python${ver}-venv" "python${ver}-dev"; then
                INSTALLED_PYTHON_VERSIONS+=("$ver")
            else
                warn "Python ${ver} not available for ${OS_CODENAME} (Ubuntu may already ship it as the system default) — skipped"
            fi
        done

        if [[ ${#INSTALLED_PYTHON_VERSIONS[@]} -eq 1 ]]; then
            DEFAULT_PYTHON="${INSTALLED_PYTHON_VERSIONS[0]}"
            info "Only one Python version installed — setting ${DEFAULT_PYTHON} as default automatically."
        elif [[ ${#INSTALLED_PYTHON_VERSIONS[@]} -gt 1 ]]; then
            echo ""
            DEFAULT_PY_OPTS=()
            for ver in "${INSTALLED_PYTHON_VERSIONS[@]}"; do
                DEFAULT_PY_OPTS+=("Python ${ver}")
            done
            pick_one "Which installed Python version should the plain 'python' command point to?" "${DEFAULT_PY_OPTS[@]}"
            DEFAULT_PYTHON=$(echo "$PICK" | grep -oP '[\d.]+' | head -1)
        fi

        if [[ -n "${DEFAULT_PYTHON:-}" ]]; then
            # Remove ALL existing python alternatives first so stale entries
            # from previous script runs can't override the user's choice.
            update-alternatives --remove-all python &>/dev/null || true

            # Re-register only the versions installed in THIS run, assigning
            # the default version the highest priority so --set is guaranteed.
            ALT_PRIORITY=10
            for ver in "${INSTALLED_PYTHON_VERSIONS[@]}"; do
                bin="/usr/bin/python${ver}"
                if [[ -x "$bin" ]]; then
                    local prio=$ALT_PRIORITY
                    [[ "$ver" == "$DEFAULT_PYTHON" ]] && prio=9999
                    update-alternatives --install /usr/bin/python python "$bin" "$prio" &>/dev/null
                    ALT_PRIORITY=$((ALT_PRIORITY+10))
                fi
            done
            update-alternatives --set python "/usr/bin/python${DEFAULT_PYTHON}" &>/dev/null
            success "'python' -> Python ${DEFAULT_PYTHON}  (change later with: sudo update-alternatives --config python)"
            info "'python3' is left untouched — it stays the Ubuntu system interpreter."

            # Warn about other python versions on disk not installed this run
            LEFTOVER_PY=()
            for bin in /usr/bin/python3.[0-9]*; do
                ver=$(echo "$bin" | grep -oP '3\.\d+' | head -1)
                [[ -z "$ver" ]] && continue
                [[ "$bin" == *-config ]] && continue
                if ! printf '%s\n' "${INSTALLED_PYTHON_VERSIONS[@]}" | grep -qx "$ver"; then
                    LEFTOVER_PY+=("$ver")
                fi
            done
            if [[ ${#LEFTOVER_PY[@]} -gt 0 ]]; then
                warn "These Python versions are on disk from a PREVIOUS script run: ${LEFTOVER_PY[*]}"
                warn "They do NOT affect the 'python' command (alternatives cleared above) but the binaries"
                warn "  python${LEFTOVER_PY[0]}, etc. are still callable directly."
                warn "To remove them:  sudo apt-get purge $(printf 'python%s ' "${LEFTOVER_PY[@]}")"
            fi

            echo ""
            info "Installed Python versions summary:"
            for ver in "${INSTALLED_PYTHON_VERSIONS[@]}"; do
                if [[ "$ver" == "$DEFAULT_PYTHON" ]]; then
                    echo -e "  ${GREEN}●${RESET} ${BOLD}${ver}${RESET} (default for 'python')"
                else
                    echo -e "  ${CYAN}●${RESET} ${ver} (call directly as python${ver})"
                fi
            done
        fi
    fi
fi

# ════════════════════════════════════════════════════════════
#  SECTION 10 — SSL via Let's Encrypt (always installed)
# ════════════════════════════════════════════════════════════
step "STEP 9 — SSL via Let's Encrypt (Certbot)"

info "Installing Certbot for Let's Encrypt SSL..."

CERTBOT_PKGS=(certbot)
case "$WEB_SERVER" in
    "Apache2")
        CERTBOT_PKGS+=(python3-certbot-apache)
        ;;
    "Nginx")
        CERTBOT_PKGS+=(python3-certbot-nginx)
        ;;
    "Both (Apache2 on 80/443, Nginx on 8080)")
        CERTBOT_PKGS+=(python3-certbot-apache python3-certbot-nginx)
        ;;
esac

run_spin "Installing Certbot" apt-get install -y -qq "${CERTBOT_PKGS[@]}"
success "Certbot installed"
divider
case "$WEB_SERVER" in
    "Apache2")
        info "Apache : certbot --apache  -d yourdomain.com"
        ;;
    "Nginx")
        info "Nginx  : certbot --nginx   -d yourdomain.com"
        ;;
    "Both (Apache2 on 80/443, Nginx on 8080)")
        info "Apache : certbot --apache  -d yourdomain.com"
        info "Nginx  : certbot --nginx   -d yourdomain.com"
        ;;
esac
info "Renewal: certbot renew --dry-run"
info "Auto-renewal is enabled via systemd timer automatically"

# ════════════════════════════════════════════════════════════
#  FINAL VERIFICATION
# ════════════════════════════════════════════════════════════
step "FINAL VERIFICATION & HEALTH CHECK"

# ── 1. Service Status ────────────────────────────────────────
echo -e "\n${BOLD}  1) Service Status${RESET}"
divider

FAILED_SVCS=()
declare -A SVCS=(
    [apache2]="Apache2"
    [nginx]="Nginx"
    [mysql]="MySQL"
    [mariadb]="MariaDB"
    [mongod]="MongoDB"
    [postgresql]="PostgreSQL"
)
for svc in "${!SVCS[@]}"; do
    systemctl list-units --full --all 2>/dev/null | grep -q "${svc}.service" || continue
    if systemctl is-active --quiet "$svc" 2>/dev/null; then
        echo -e "  ${GREEN}✔${RESET}  ${SVCS[$svc]}"
    else
        echo -e "  ${RED}✘${RESET}  ${SVCS[$svc]} ${DIM}— not running!${RESET}"
        FAILED_SVCS+=("${SVCS[$svc]}")
    fi
done

# PHP-FPM per version
for ver in "${ALL_PHP_VERSIONS[@]}"; do
    svc="php${ver}-fpm"
    systemctl list-units --full --all 2>/dev/null | grep -q "${svc}.service" || continue
    if systemctl is-active --quiet "$svc" 2>/dev/null; then
        echo -e "  ${GREEN}✔${RESET}  PHP-FPM ${ver}"
    else
        echo -e "  ${RED}✘${RESET}  PHP-FPM ${ver} ${DIM}— not running!${RESET}"
        FAILED_SVCS+=("PHP-FPM ${ver}")
    fi
done

# ── 2. Installed Versions ────────────────────────────────────
echo -e "\n${BOLD}  2) Installed Versions${RESET}"
divider
command -v apache2 &>/dev/null &&     echo -e "  ${GREEN}●${RESET}  Apache   : $(apache2 -v 2>&1 | grep 'Server version' | awk '{print $3}')"
command -v nginx   &>/dev/null &&     echo -e "  ${GREEN}●${RESET}  Nginx    : $(nginx -v 2>&1 | grep -oP 'nginx/[\d.]+')"
command -v mysql   &>/dev/null &&     echo -e "  ${GREEN}●${RESET}  MySQL    : $(mysql --version 2>&1 | awk '{print $1, $3}' | tr -d ',')"
command -v mariadb &>/dev/null &&     echo -e "  ${GREEN}●${RESET}  MariaDB  : $(mariadb --version 2>&1 | awk '{print $1, $5}' | tr -d ',')"
command -v psql    &>/dev/null &&     echo -e "  ${GREEN}●${RESET}  Postgres : $(psql --version 2>&1)"
command -v mongod  &>/dev/null &&     echo -e "  ${GREEN}●${RESET}  MongoDB  : $(mongod --version 2>&1 | head -1)"
command -v certbot &>/dev/null &&     echo -e "  ${GREEN}●${RESET}  Certbot  : $(certbot --version 2>&1)"
[[ -x /usr/local/bin/node ]] &&     echo -e "  ${GREEN}●${RESET}  Node     : $(/usr/local/bin/node --version 2>&1) (default)"
command -v python &>/dev/null &&     echo -e "  ${GREEN}●${RESET}  python   : $(python --version 2>&1) (default alternative)"

# PHP versions + loaded extensions
echo ""
for ver in "${ALL_PHP_VERSIONS[@]}"; do
    bin="/usr/bin/php${ver}"
    [[ -x "$bin" ]] || continue
    exts=$($bin -m 2>/dev/null | grep -iE "mysql|curl|gd|mbstring|xml|zip|opcache|intl|bcmath" | tr '
' ' ')
    echo -e "  ${GREEN}●${RESET}  PHP ${ver}  : $($bin -r 'echo PHP_VERSION;' 2>/dev/null)  ${DIM}[${exts}]${RESET}"
done

# ── 3. Open Ports ────────────────────────────────────────────
echo -e "\n${BOLD}  3) Listening Ports${RESET}"
divider
ss -tlnp | grep -E ':80 |:443 |:3306 |:5432 |:8080 |:27017 |:35001 '     | awk '{print "  " $4}' | sort -u

# ── 4. PHP-FPM Socket / Config Check ────────────────────────
echo -e "\n${BOLD}  4) PHP-FPM Pool Sockets${RESET}"
divider
for sock in /run/php/php*-fpm.sock; do
    [[ -S "$sock" ]] && echo -e "  ${GREEN}✔${RESET}  $sock"                      || true
done

# ── 5. Web Server Config Test ────────────────────────────────
echo -e "\n${BOLD}  5) Web Server Config Test${RESET}"
divider
if command -v apache2 &>/dev/null; then
    if apache2ctl configtest 2>&1 | grep -q "Syntax OK"; then
        echo -e "  ${GREEN}✔${RESET}  Apache config — Syntax OK"
    else
        echo -e "  ${RED}✘${RESET}  Apache config — ERRORS found"
        apache2ctl configtest 2>&1 | grep -v "^$" | while IFS= read -r l; do
            echo -e "    ${RED}${l}${RESET}"
        done
    fi
fi
if command -v nginx &>/dev/null; then
    if nginx -t 2>&1 | grep -q "successful"; then
        echo -e "  ${GREEN}✔${RESET}  Nginx config — Syntax OK"
    else
        echo -e "  ${RED}✘${RESET}  Nginx config — ERRORS found"
        nginx -t 2>&1 | grep -v "^$" | while IFS= read -r l; do
            echo -e "    ${RED}${l}${RESET}"
        done
    fi
fi

# ── 6. Disk & Memory After Install ──────────────────────────
echo -e "\n${BOLD}  6) Resource Usage After Install${RESET}"
divider
DISK_USED=$(df -BG / | awk 'NR==2{print $3}')
DISK_FREE=$(df -BG / | awk 'NR==2{print $4}')
MEM_USED=$(free -m | awk '/^Mem:/{print $3}')
MEM_FREE=$(free -m | awk '/^Mem:/{print $4}')
echo -e "  Disk used : ${DISK_USED}  |  Free: ${DISK_FREE}"
echo -e "  RAM  used : ${MEM_USED}MB  |  Free: ${MEM_FREE}MB"

# ── Summary ──────────────────────────────────────────────────
echo ""
divider
if [[ ${#FAILED_SVCS[@]} -gt 0 ]]; then
    echo -e "  ${RED}${BOLD}⚠  ${#FAILED_SVCS[@]} service(s) not running:${RESET}"
    for s in "${FAILED_SVCS[@]}"; do
        echo -e "    ${RED}✘  ${s}${RESET}"
    done
else
    echo -e "  ${GREEN}${BOLD}✔  All installed services are running!${RESET}"
fi

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
