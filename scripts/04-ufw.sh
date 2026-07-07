#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
ENV_FILE="${REPO_DIR}/.env"

if [ -f "${ENV_FILE}" ]; then
  set -a
  # shellcheck disable=SC1090
  source "${ENV_FILE}"
  set +a
fi

COCKPIT_PORT="${COCKPIT_PORT:-9090}"

if [ "$(id -u)" -ne 0 ]; then
  echo "ERROR: Run this script as root or with sudo."
  exit 1
fi

echo "IMPORTANT: Run this only after you confirmed SSH access works."
echo "Current SSH sessions should remain connected, but keep your VPS provider console available."
read -r -p "Continue configuring UFW? [y/N] " answer

case "${answer}" in
  y|Y|yes|YES) ;;
  *) echo "Aborted."; exit 0 ;;
esac

echo "==> Resetting UFW rules..."
ufw --force reset

echo "==> Setting defaults..."
ufw default deny incoming
ufw default allow outgoing

echo "==> Allowing public SSH temporarily..."
ufw allow 22/tcp comment 'SSH temporary public access'

echo "==> Allowing public HTTP/HTTPS..."
ufw allow 80/tcp comment 'HTTP'
ufw allow 443/tcp comment 'HTTPS'

echo "==> Allowing Cockpit only through Tailscale interface..."
ufw allow in on tailscale0 to any port "${COCKPIT_PORT}" proto tcp comment 'Cockpit via Tailscale'

echo "==> Allowing all traffic over Tailscale interface..."
ufw allow in on tailscale0 comment 'Tailscale inbound'

echo "==> Enabling UFW..."
ufw --force enable

echo "==> UFW status:"
ufw status verbose
