#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

STACK_DIR=/opt/inventree
DATA_DIR=/srv/inventree
TEMPLATE_REF=be488919e4928cf16140b85d77058115a89cb4ef
SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"

usage() {
    printf '%s\n' \
        'Usage: bash inventree.sh provision' \
        '       bash inventree.sh deploy DOMAIN RELEASE_VERSION' \
        '       bash inventree.sh backup|status' \
        '       bash inventree.sh upgrade RELEASE_VERSION' \
        'Run on Debian as root. Deploy requires public DNS and inbound TCP 80/443.'
}

die() { printf 'Error: %s\n' "$*" >&2; exit 1; }

validate_version() {
    [[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die 'Use an explicit stable release, such as 1.6.0; floating tags are not allowed.'
}

validate_domain() {
    local label
    local -a labels
    [[ "$1" =~ ^[a-zA-Z0-9]([a-zA-Z0-9.-]*[a-zA-Z0-9])?$ && "$1" == *.* && "$1" != *..* ]] || die 'Provide a DNS hostname without scheme, port, path, or spaces.'
    [[ ! "$1" =~ ^[0-9.]+$ ]] || die 'Provide a DNS hostname, not an IP address.'
    [[ "${#1}" -le 253 ]] || die 'Hostname exceeds DNS length limits.'
    IFS=. read -r -a labels <<< "$1"
    for label in "${labels[@]}"; do
        [[ "${#label}" -le 63 && "$label" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?$ ]] || die 'Hostname contains an invalid DNS label.'
    done
}

require_host() {
    [[ "$EUID" -eq 0 ]] || die 'Run as root on the Debian server.'
    [[ -r /etc/os-release ]] || die 'Cannot identify operating system.'
    . /etc/os-release
    [[ "$ID" == debian && ( "$VERSION_ID" == 12 || "$VERSION_ID" == 13 ) ]] || die 'Supported hosts: Debian 12 or 13.'
    [[ "$STACK_DIR" == /* && "$DATA_DIR" == /* && "$STACK_DIR" != / && "$DATA_DIR" != / ]] || die 'Deployment and data directories must be absolute, non-root paths.'
}

compose() { (cd "$STACK_DIR" && docker compose "$@"); }

require_stack() {
    [[ -f "$STACK_DIR/.env" && -f "$STACK_DIR/docker-compose.yml" ]] || die 'Deploy the stack first.'
}

provision() {
    apt-get update
    apt-get install -y ca-certificates curl openssl
    if ! command -v docker >/dev/null 2>&1; then
        for package in docker.io docker-compose podman-docker containerd runc; do
            if dpkg-query -W -f='${Status}' "$package" 2>/dev/null | grep -q 'install ok installed'; then
                die "Conflicting package $package is installed. Review Docker's Debian migration instructions first."
            fi
        done
        install -m 0755 -d /etc/apt/keyrings
        curl --fail --silent --show-error --location https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
        chmod 0644 /etc/apt/keyrings/docker.asc
        printf 'deb [arch=%s signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian %s stable\n' \
            "$(dpkg --print-architecture)" "$VERSION_CODENAME" > /etc/apt/sources.list.d/docker.list
        apt-get update
        apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    fi
    docker compose version >/dev/null
    systemctl enable --now docker
    docker run --rm hello-world
}

download_templates() {
    local filename temporary
    for filename in docker-compose.yml Caddyfile; do
        temporary="$(mktemp "$STACK_DIR/.download.XXXXXX")"
        if ! curl --fail --silent --show-error --location \
            "https://raw.githubusercontent.com/inventree/inventree/$TEMPLATE_REF/contrib/container/$filename" -o "$temporary"; then
            rm -f "$temporary"
            die "Could not download $filename."
        fi
        mv "$temporary" "$STACK_DIR/$filename"
    done
}

write_environment() {
    local domain="$1" version="$2" database_password admin_password
    database_password="$(openssl rand -hex 32)"
    admin_password="$(openssl rand -hex 24)"
    cat > "$STACK_DIR/.env" <<EOF
COMPOSE_PROJECT_NAME=inventree
INVENTREE_TAG=$version
INVENTREE_SITE_URL=https://$domain
INVENTREE_EXT_VOLUME=$DATA_DIR
INVENTREE_WEB_PORT=8000
INVENTREE_USE_X_FORWARDED_HOST=True
INVENTREE_USE_X_FORWARDED_PORT=True
INVENTREE_USE_X_FORWARDED_PROTO=True
INVENTREE_DEBUG=False
INVENTREE_LOG_LEVEL=WARNING
INVENTREE_PLUGINS_ENABLED=False
INVENTREE_AUTO_UPDATE=False
INVENTREE_DB_ENGINE=postgresql
INVENTREE_DB_NAME=inventree
INVENTREE_DB_HOST=inventree-db
INVENTREE_DB_PORT=5432
INVENTREE_DB_USER=inventree
INVENTREE_DB_PASSWORD=$database_password
INVENTREE_CACHE_ENABLED=True
INVENTREE_CACHE_HOST=inventree-cache
INVENTREE_CACHE_PORT=6379
INVENTREE_GUNICORN_TIMEOUT=90
INVENTREE_ADMIN_USER=admin
INVENTREE_ADMIN_EMAIL=admin@$domain
INVENTREE_ADMIN_PASSWORD=$admin_password
EOF
    printf 'URL: https://%s\nUsername: admin\nPassword: %s\nChange this password after login, then remove this file.\n' \
        "$domain" "$admin_password" > "$STACK_DIR/initial-admin.txt"
    chmod 0600 "$STACK_DIR/.env" "$STACK_DIR/initial-admin.txt"
}

remove_bootstrap_credentials() {
    local temporary
    temporary="$(mktemp "$STACK_DIR/.env.XXXXXX")"
    grep -v '^INVENTREE_ADMIN_' "$STACK_DIR/.env" > "$temporary"
    chmod 0600 "$temporary"
    mv "$temporary" "$STACK_DIR/.env"
}

install_backup_timer() {
    [[ "$STACK_DIR" == /opt/inventree && "$DATA_DIR" == /srv/inventree ]] || die 'Automatic timer installation requires the default deployment paths.'
    if [[ "$SCRIPT_PATH" != "$STACK_DIR/inventree.sh" ]]; then
        install -m 0750 "$SCRIPT_PATH" "$STACK_DIR/inventree.sh"
    fi
    cat > /etc/systemd/system/inventree-backup.service <<EOF
[Unit]
Description=Back up InvenTree database and media
Requires=docker.service
After=docker.service
[Service]
Type=oneshot
ExecStart=/bin/bash /opt/inventree/inventree.sh backup
UMask=0077
EOF
    cat > /etc/systemd/system/inventree-backup.timer <<EOF
[Unit]
Description=Daily InvenTree backup
[Timer]
OnCalendar=*-*-* 02:30:00
RandomizedDelaySec=15m
Persistent=true
[Install]
WantedBy=timers.target
EOF
    systemctl daemon-reload
    systemctl enable --now inventree-backup.timer
}

deploy() {
    local domain="$1" version="$2"
    validate_domain "$domain"
    validate_version "$version"
    [[ ! -e "$STACK_DIR/.env" ]] || die 'Existing configuration found; use upgrade or recover the interrupted deployment manually.'
    [[ ! -d "$DATA_DIR" || -z "$(ls -A "$DATA_DIR")" ]] || die 'Data directory is not empty; refusing a fresh deployment.'
    install -d -m 0700 "$STACK_DIR"
    install -d -m 0755 "$DATA_DIR"
    download_templates
    write_environment "$domain" "$version"
    compose config --quiet
    compose pull
    compose run --rm inventree-server invoke update
    compose up -d --wait --wait-timeout 600
    remove_bootstrap_credentials
    compose up -d --wait --wait-timeout 600
    install_backup_timer
    printf 'Deployment healthy. Initial login is stored in %s/initial-admin.txt (root only).\n' "$STACK_DIR"
    printf 'Configure off-machine backups, SMTP, firewall policy, and alerting before production use.\n'
}

backup() {
    require_stack
    compose exec -T inventree-server invoke backup
    printf 'Database and media backup completed. Copy backups and deployment secrets to encrypted off-machine storage.\n'
}

upgrade() {
    local version="$1" previous temporary
    require_stack
    validate_version "$version"
    previous="$(sed -n 's/^INVENTREE_TAG=//p' "$STACK_DIR/.env")"
    [[ -n "$previous" ]] || die 'Cannot identify the current release.'
    [[ "$version" != "$previous" ]] || die 'The requested version is already configured.'
    [[ "$(printf '%s\n%s\n' "$previous" "$version" | sort -V | head -n 1)" == "$previous" ]] || die 'Downgrades require restoring a matching backup; they are not automated.'
    compose stop inventree-proxy inventree-worker
    backup
    cp -p "$STACK_DIR/.env" "$STACK_DIR/.env.before-upgrade"
    temporary="$(mktemp "$STACK_DIR/.env.XXXXXX")"
    sed "s/^INVENTREE_TAG=.*/INVENTREE_TAG=$version/" "$STACK_DIR/.env" > "$temporary"
    mv "$temporary" "$STACK_DIR/.env"
    compose pull inventree-server inventree-worker
    compose stop inventree-server
    compose run --rm inventree-server invoke update
    compose up -d --wait --wait-timeout 600
    printf 'Upgrade healthy. Keep the pre-upgrade backup; database rollback is not automatic.\n'
}

main() {
    local action="${1:---help}"
    case "$action" in
        -h|--help) usage; return ;;
        provision|backup|status) [[ "$#" -eq 1 ]] || die 'Unexpected arguments.' ;;
        deploy) [[ "$#" -eq 3 ]] || die 'Usage: deploy DOMAIN RELEASE_VERSION' ;;
        upgrade) [[ "$#" -eq 2 ]] || die 'Usage: upgrade RELEASE_VERSION' ;;
        *) usage; die 'Unknown command.' ;;
    esac
    require_host
    install -d -m 0700 "$STACK_DIR"
    exec 9> "$STACK_DIR/.deploy.lock"
    flock -n 9 || die 'Another deployment or backup is running.'
    case "$action" in
        provision) provision ;;
        deploy) deploy "$2" "$3" ;;
        backup) backup ;;
        upgrade) upgrade "$2" ;;
        status) require_stack; compose ps; compose logs --tail=50 ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi