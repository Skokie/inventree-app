#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$ROOT/inventree.sh"
TEMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEMP_ROOT"' EXIT
STACK_DIR="$TEMP_ROOT/stack"
DATA_DIR="$TEMP_ROOT/data"
mkdir -p "$STACK_DIR"
LOG="$TEMP_ROOT/commands"

assert_rejected() {
    if ("$@") > "$TEMP_ROOT/rejected.log" 2>&1; then
        die "Expected rejection: $*"
    fi
}

compose() { printf '%s\n' "$*" >> "$LOG"; }
download_templates() {
    printf 'services: {}\n' > "$STACK_DIR/docker-compose.yml"
    printf 'example.test {}\n' > "$STACK_DIR/Caddyfile"
}
install_backup_timer() { printf 'timer installed\n' >> "$LOG"; }

validate_domain inventory.example.com
validate_version 1.6.0
assert_rejected validate_domain https://inventory.example.com
assert_rejected validate_domain 192.168.1.10
assert_rejected validate_domain 'example.com/path'
assert_rejected validate_domain 'example.com;id'
assert_rejected validate_domain 'inventory.-example.com'
assert_rejected validate_domain 'inventory.example-.com'
assert_rejected validate_version latest
assert_rejected validate_version stable
assert_rejected validate_version '1.6.0;id'

deploy inventory.example.com 1.6.0 > "$TEMP_ROOT/deploy.log"
grep -q '^INVENTREE_DEBUG=False$' "$STACK_DIR/.env"
grep -q '^INVENTREE_TAG=1.6.0$' "$STACK_DIR/.env"
grep -Eq '^INVENTREE_DB_PASSWORD=[a-f0-9]{64}$' "$STACK_DIR/.env"
grep -Eq '^Password: [a-f0-9]{48}$' "$STACK_DIR/initial-admin.txt"
[[ -n "$(find "$STACK_DIR/.env" -perm 0600)" ]]
[[ -n "$(find "$STACK_DIR/initial-admin.txt" -perm 0600)" ]]
if grep -q '^INVENTREE_ADMIN_' "$STACK_DIR/.env"; then die 'Bootstrap credentials survived deployment.'; fi
if grep -q '^Password:' "$TEMP_ROOT/deploy.log"; then die 'Credentials leaked to deployment output.'; fi
[[ "$(grep -c '^up -d --wait' "$LOG")" -eq 2 ]]
grep -q '^timer installed$' "$LOG"
assert_rejected deploy inventory.example.com 1.6.0
assert_rejected upgrade 1.6.0
assert_rejected upgrade 1.5.0

: > "$LOG"
upgrade 1.6.1 > "$TEMP_ROOT/upgrade.log"
grep -q '^INVENTREE_TAG=1.6.1$' "$STACK_DIR/.env"
grep -q '^INVENTREE_TAG=1.6.0$' "$STACK_DIR/.env.before-upgrade"
expected=$'stop inventree-proxy inventree-worker\nexec -T inventree-server invoke backup\npull inventree-server inventree-worker\nstop inventree-server\nrun --rm inventree-server invoke update\nup -d --wait --wait-timeout 600'
[[ "$(cat "$LOG")" == "$expected" ]] || die 'Unsafe upgrade ordering.'

: > "$LOG"
compose() {
    printf '%s\n' "$*" >> "$LOG"
    if [[ "$*" == 'pull inventree-server inventree-worker' ]]; then die 'Simulated image pull failure.'; fi
}
assert_rejected upgrade 1.6.2
if grep -q 'invoke update' "$LOG"; then die 'Migration ran after failed image pull.'; fi

rm "$STACK_DIR/.env"
printf 'existing data\n' > "$DATA_DIR/existing-record"
assert_rejected deploy inventory.example.com 1.6.0
printf 'All deployment tests passed (Docker and systemd mocked).\n'