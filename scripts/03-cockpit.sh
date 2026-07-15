#!/usr/bin/env bash
set -euo pipefail
umask 027

export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a

if [ "$(id -u)" -ne 0 ]; then
  echo "ERROR: Run this script as root or with sudo."
  exit 1
fi

prompt_optional() {
  local var_name="$1"
  local prompt_text="$2"
  local default_value="$3"
  local value="${!var_name:-}"

  if [ -z "${value}" ]; then
    read -r -p "${prompt_text} [${default_value}]: " value </dev/tty
    value="${value:-$default_value}"
  fi

  printf -v "${var_name}" '%s' "${value}"
  export "${var_name}"
}

validate_port() {
  local port="$1"

  if ! [[ "${port}" =~ ^[0-9]+$ ]]; then
    echo "ERROR: Invalid port: ${port}"
    exit 1
  fi

  if [ "${port}" -lt 1 ] || [ "${port}" -gt 65535 ]; then
    echo "ERROR: Port must be between 1 and 65535."
    exit 1
  fi
}

confirm_continue() {
  if [ "${ASSUME_YES:-false}" = "true" ]; then
    return 0
  fi

  local answer=""
  read -r -p "Continue? [y/N]: " answer </dev/tty

  case "${answer}" in
    y|Y|yes|YES)
      ;;
    *)
      echo "Aborted."
      exit 0
      ;;
  esac
}

prompt_optional "COCKPIT_PORT" "Enter Cockpit port" "9090"
validate_port "${COCKPIT_PORT}"

TAILSCALE_IP=""

if command -v tailscale >/dev/null 2>&1; then
  TAILSCALE_IP="$(tailscale ip -4 2>/dev/null | head -n1 || true)"
fi

case "${ALLOW_PUBLIC_COCKPIT:-false}" in
  true|TRUE|yes|YES|y|Y|1)
    ALLOW_PUBLIC_COCKPIT=true
    ;;
  false|FALSE|no|NO|n|N|0)
    ALLOW_PUBLIC_COCKPIT=false
    ;;
  *)
    echo "ERROR: ALLOW_PUBLIC_COCKPIT must be true or false."
    exit 1
    ;;
esac

if [ -z "${TAILSCALE_IP}" ] && [ "${ALLOW_PUBLIC_COCKPIT}" != "true" ]; then
  echo "ERROR: No Tailscale IPv4 address was detected."
  echo "Cockpit will not be installed with a public/default bind."
  echo "Connect Tailscale first, or explicitly set ALLOW_PUBLIC_COCKPIT=true."
  exit 1
fi

echo
echo "==> Cockpit setup summary"
echo "Port:        ${COCKPIT_PORT}"

if [ -n "${TAILSCALE_IP}" ]; then
  echo "Bind mode:   Tailscale only"
  echo "Bind IP:     ${TAILSCALE_IP}"
else
  echo "Bind mode:   Cockpit default (explicitly allowed)"
  echo "Bind IP:     default"
fi

echo
confirm_continue

echo "==> Installing Cockpit..."
apt-get update
apt-get install -y cockpit

OVERRIDE_DIR="/etc/systemd/system/cockpit.socket.d"
OVERRIDE_FILE="${OVERRIDE_DIR}/listen.conf"

if [ -n "${TAILSCALE_IP}" ]; then
  echo "==> Binding Cockpit to Tailscale IP..."

  mkdir -p "${OVERRIDE_DIR}"

  cat >"${OVERRIDE_FILE}" <<EOF
[Socket]
ListenStream=
ListenStream=${TAILSCALE_IP}:${COCKPIT_PORT}
FreeBind=yes
EOF

  echo "==> Cockpit will listen on ${TAILSCALE_IP}:${COCKPIT_PORT}"
else
  echo "==> Tailscale IP not found; public/default Cockpit binding was explicitly allowed."
  echo "==> Removing custom Cockpit bind override if present..."

  if [ -f "${OVERRIDE_FILE}" ]; then
    rm -f "${OVERRIDE_FILE}"
  fi

  if [ -d "${OVERRIDE_DIR}" ] && [ -z "$(ls -A "${OVERRIDE_DIR}")" ]; then
    rmdir "${OVERRIDE_DIR}"
  fi

  echo "==> Cockpit will use its default socket configuration."
fi

echo "==> Enabling Cockpit socket..."
systemctl daemon-reload
systemctl enable --now cockpit.socket
systemctl restart cockpit.socket

echo
echo "==> Cockpit socket status:"
systemctl is-active cockpit.socket || true

echo
echo "Cockpit should be available at:"

if [ -n "${TAILSCALE_IP}" ]; then
  echo "  https://${TAILSCALE_IP}:${COCKPIT_PORT}"
else
  echo "  https://SERVER_IP:${COCKPIT_PORT}"
fi
