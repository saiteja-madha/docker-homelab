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

echo "==> Installing Cockpit..."
apt update
apt install -y cockpit

echo "==> Enabling Cockpit socket..."
systemctl enable --now cockpit.socket

echo "==> Cockpit status:"
systemctl status cockpit.socket --no-pager || true

echo
echo "Cockpit should be available at:"
echo "  https://SERVER_IP:${COCKPIT_PORT}"
echo "Recommended after Tailscale:"
echo "  https://TAILSCALE_IP:${COCKPIT_PORT}"
