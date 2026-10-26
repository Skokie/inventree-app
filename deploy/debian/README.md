# Debian Production Deployment

These scripts deploy the official InvenTree server, not the Flutter app, on a
dedicated Debian 12 or 13 host. They are intended for a fresh installation with
a DNS hostname and publicly reachable TCP ports 80 and 443. Caddy obtains HTTPS
certificates automatically. Private-only networks need a separate certificate
and proxy plan; this script does not configure one.

## Prepare The Host

Assign a fixed address, point your hostname's DNS at it, update Debian, and
configure SSH key access. Restrict SSH to administrators. Permit inbound TCP
80/443, but do not expose PostgreSQL, Redis, or port 8000. Docker-published ports
can bypass UFW: apply Docker-compatible or upstream firewall rules. Firewall,
DNS, SMTP, and off-machine backup configuration are intentionally not automated.

Run the following on the Debian machine, not on your development Mac:

```bash
sudo apt update
sudo apt install -y git
git clone https://github.com/Skokie/inventree-app.git
cd inventree-app
less deploy/debian/inventree.sh
sudo bash deploy/debian/inventree.sh provision
sudo bash deploy/debian/inventree.sh deploy inventory.example.com RELEASE_VERSION
```

Replace `inventory.example.com` and `RELEASE_VERSION` with your hostname and an
existing stable InvenTree release tag, such as `1.6.0` if that release is suitable
for your deployment. Verify available releases and release notes first; the
example is not a recommendation of the latest release. Floating `stable` and
`latest` tags are rejected. Provisioning does not remove conflicting Docker
packages, change your firewall, grant Docker group membership, or upgrade Debian.

The script downloads the official Compose and Caddy templates from immutable
upstream commit `be488919e4928cf16140b85d77058115a89cb4ef`. Review template
compatibility when choosing a release, especially for older server versions.
PostgreSQL 17, Redis, Caddy, the server, and its worker run as containers.

## Initial Login And Data

Configuration lives in `/opt/inventree`; persistent data lives in `/srv/inventree`.
Database and administrator passwords are generated locally. Deployment output
does not print them. Read the initial login on the server:

```bash
sudo cat /opt/inventree/initial-admin.txt
```

Change the administrator password after login, then remove that file. Bootstrap
administrator variables are removed from `.env` after startup and containers are
recreated without them. Protect `.env`, backups, configuration, and secret-key
material; never commit them. Debug mode and plugins are disabled by default.
The official image includes the frontend, and Caddy serves static/media files.

An existing `.env` or nonempty data directory prevents a fresh deployment.
If deployment is interrupted, inspect `/opt/inventree/.env` and Compose logs,
correct the cause, then resume the relevant commands manually. Do not delete
data just to bypass this protection. Existing SQLite development databases
cannot be copied into PostgreSQL: plan a version-compatible migration separately.

## Operations

The deployed script is installed at `/opt/inventree/inventree.sh`:

```bash
sudo bash /opt/inventree/inventree.sh status
sudo bash /opt/inventree/inventree.sh backup
sudo systemctl list-timers inventree-backup.timer
sudo journalctl -u inventree-backup.service
sudo bash /opt/inventree/inventree.sh upgrade NEW_RELEASE_VERSION
```

The timer runs database/media backups daily at approximately 02:30, including a
catch-up run after downtime. Configure encrypted off-machine copies, retention,
disk-space monitoring, and failure alerts. Local backups alone do not protect
against disk loss. Back up deployment configuration and secret-key material too.
Test restores on an isolated host with the same InvenTree and PostgreSQL versions;
use the official `invoke restore` procedure. Do not archive a live PostgreSQL
directory as your only database backup.

Upgrades stop ingress and the worker, create a backup, preserve `.env` as
`.env.before-upgrade`, pull the requested app image, migrate, and wait for health.
They do not automatically change PostgreSQL, Redis, Caddy, or deployment templates.
Review release notes and test on staging first. Failed upgrades leave the stack
in maintenance mode for investigation; rollback is not automatic and may require
the pre-upgrade database/media backup. Downgrades are rejected. Never use
`docker compose down -v` as an upgrade or recovery command.

## Verification

```bash
for script in deploy/debian/*.sh; do bash -n "$script"; done
bash deploy/debian/test.sh
shellcheck -x deploy/debian/inventree.sh
```

The shell tests mock Docker and systemd: they do not replace a Debian deployment
test. After deployment, verify container health, valid HTTPS, login, attachment
upload/download, worker health, mobile-app connectivity, and a backup restore.
Configure Docker log rotation and host security updates before production use.

References: [official installation](https://docs.inventree.org/en/stable/start/docker_install/),
[Docker on Debian](https://docs.docker.com/engine/install/debian/),
and [backup/restore](https://docs.inventree.org/en/stable/start/backup/).