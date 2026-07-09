#!/usr/bin/env bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

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
  read -r -p "Continue configuring UFW? [y/N]: " answer </dev/tty

  case "${answer}" in
    y|Y|yes|YES)
      ;;
    *)
      echo "Aborted."
      exit 0
      ;;
  esac
}

bool_value() {
  case "${1:-}" in
    true|TRUE|yes|YES|y|Y|1)
      echo "true"
      ;;
    false|FALSE|no|NO|n|N|0)
      echo "false"
      ;;
    *)
      echo "ERROR: Invalid boolean value: ${1}" >&2
      echo "Use true or false." >&2
      exit 1
      ;;
  esac
}

prompt_optional "SSH_PORT" "Enter SSH port" "22"
validate_port "${SSH_PORT}"

ALLOW_PUBLIC_SSH="$(bool_value "${ALLOW_PUBLIC_SSH:-true}")"
RESET_UFW="$(bool_value "${RESET_UFW:-true}")"

TAILSCALE_AVAILABLE=false
TAILSCALE_IP=""

if command -v tailscale >/dev/null 2>&1 && ip link show tailscale0 >/dev/null 2>&1; then
  TAILSCALE_IP="$(tailscale ip -4 2>/dev/null | head -n1 || true)"

  if [ -n "${TAILSCALE_IP}" ]; then
    TAILSCALE_AVAILABLE=true
  fi
fi

echo
echo "IMPORTANT:"
echo "Run this only after you confirmed SSH access works."
echo "Current SSH sessions should usually remain connected, but keep your VPS provider console available."
echo
echo "==> UFW setup summary"
echo "SSH port:           ${SSH_PORT}"
echo "Reset UFW rules:    ${RESET_UFW}"
echo "Allow public SSH:   ${ALLOW_PUBLIC_SSH}"
echo "Tailscale detected: ${TAILSCALE_AVAILABLE}"

if [ -n "${TAILSCALE_IP}" ]; then
  echo "Tailscale IPv4:     ${TAILSCALE_IP}"
fi

echo
confirm_continue

echo "==> Installing UFW if needed..."
apt-get update
apt-get install -y ufw

if [ "${RESET_UFW}" = "true" ]; then
  echo "==> Resetting UFW rules..."
  ufw --force reset
else
  echo "==> Keeping existing UFW rules."
fi

echo "==> Setting UFW defaults..."
ufw default deny incoming
ufw default allow outgoing

if [ "${ALLOW_PUBLIC_SSH}" = "true" ]; then
  echo "==> Ensuring public SSH is allowed on port ${SSH_PORT}..."
  ufw allow "${SSH_PORT}/tcp" comment 'SSH temporary public access'
else
  echo "==> Public SSH will not be added."

  if ufw status numbered | grep -q "${SSH_PORT}/tcp"; then
    echo "==> Existing SSH rule for ${SSH_PORT}/tcp may still exist."
    echo "==> Review with:"
    echo "    sudo ufw status numbered"
    echo "==> Delete manually only after confirming Tailscale SSH works."
  fi
fi

if [ "${TAILSCALE_AVAILABLE}" = "true" ]; then

  echo "==> Ensuring Tailscale SSH is allowed on port ${SSH_PORT}..."
  ufw allow in on tailscale0 to any port "${SSH_PORT}" proto tcp comment 'Tailscale SSH access'

  echo "==> Ensuring all inbound traffic over Tailscale is allowed..."
  ufw allow in on tailscale0 comment 'Tailscale inbound'
else
  echo "==> Tailscale not detected or no Tailscale IPv4 found."
  echo "==> Skipping Tailscale-specific UFW rules."
fi

echo "==> Enabling UFW..."
ufw --force enable

echo
echo "==> UFW status:"
ufw status verbose

if [ "${TAILSCALE_AVAILABLE}" = "true" ]; then
  cat <<EOF

NEXT STEP:
1. From another terminal, confirm SSH works over Tailscale:

   ssh -p ${SSH_PORT} user@${TAILSCALE_IP}

2. After Tailscale SSH is confirmed, manually remove the public SSH rule:

   sudo ufw status numbered
   sudo ufw delete <rule-number>

3. Confirm only Tailscale inbound remains:

   sudo ufw status verbose

EOF
else
  cat <<EOF

NEXT STEP:
Tailscale was not detected, so only public SSH may be allowed.

Before removing public SSH:
1. Install and connect Tailscale.
2. Confirm SSH over Tailscale works.
3. Rerun this script.

EOF
fi
