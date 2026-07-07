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

TAILSCALE_AUTH_KEY="${TAILSCALE_AUTH_KEY:-}"
TAILSCALE_HOSTNAME="${TAILSCALE_HOSTNAME:-}"

if [ "$(id -u)" -ne 0 ]; then
  echo "ERROR: Run this script as root or with sudo."
  exit 1
fi

echo "==> Installing Tailscale..."
curl -fsSL https://tailscale.com/install.sh | sh

echo "==> Enabling tailscaled..."
systemctl enable tailscaled
systemctl start tailscaled

UP_ARGS=()

if [ -n "${TAILSCALE_HOSTNAME}" ]; then
  UP_ARGS+=(--hostname "${TAILSCALE_HOSTNAME}")
fi

if [ -n "${TAILSCALE_AUTH_KEY}" ]; then
  echo "==> Bringing Tailscale up using auth key..."
  tailscale up --auth-key "${TAILSCALE_AUTH_KEY}" "${UP_ARGS[@]}"
else
  echo "==> Bringing Tailscale up interactively..."
  tailscale up "${UP_ARGS[@]}"
fi

echo "==> Tailscale status:"
tailscale status || true

echo
echo "Tailscale IPv4:"
tailscale ip -4 || true
