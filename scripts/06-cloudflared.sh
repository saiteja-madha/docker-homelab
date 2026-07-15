#!/usr/bin/env bash
set -euo pipefail
umask 027

export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a

if [ "$(id -u)" -ne 0 ]; then
  echo "ERROR: Run this script with sudo/root."
  exit 1
fi

prompt_secret_required() {
  local var_name="$1"
  local prompt_text="$2"
  local value="${!var_name:-}"

  while [ -z "${value}" ]; do
    read -r -s -p "${prompt_text}: " value </dev/tty
    echo >&2
    if [ -z "${value}" ]; then
      echo "ERROR: ${var_name} is required."
    fi
  done

  printf -v "${var_name}" '%s' "${value}"
  export "${var_name}"
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

is_yes() {
  case "${1:-}" in
    y|Y|yes|YES|true|TRUE|1)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

echo "==> Checking existing cloudflared service..."

SERVICE_EXISTS=false

if systemctl list-unit-files | grep -q '^cloudflared.service'; then
  SERVICE_EXISTS=true
fi

REINSTALL_CLOUDFLARED_SERVICE="false"

if [ "${SERVICE_EXISTS}" = "true" ]; then
  echo "==> Existing cloudflared service found."

  REINSTALL_CLOUDFLARED_SERVICE="${REINSTALL_CLOUDFLARED_SERVICE:-}"

  if [ -z "${REINSTALL_CLOUDFLARED_SERVICE}" ]; then
    read -r -p "Reinstall cloudflared service with a new token? [y/N]: " REINSTALL_CLOUDFLARED_SERVICE </dev/tty
  fi

  if is_yes "${REINSTALL_CLOUDFLARED_SERVICE}"; then
    REINSTALL_CLOUDFLARED_SERVICE="true"
  else
    REINSTALL_CLOUDFLARED_SERVICE="false"
  fi
else
  REINSTALL_CLOUDFLARED_SERVICE="true"
fi

if [ "${REINSTALL_CLOUDFLARED_SERVICE}" = "true" ]; then
  echo
  echo "Cloudflared tunnel token is required."
  echo
  echo "Get it from:"
  echo "  Cloudflare Zero Trust → Networks → Tunnels → Create Tunnel"
  echo

  prompt_secret_required "CLOUDFLARED_TOKEN" "Paste Cloudflared tunnel token"
else
  CLOUDFLARED_TOKEN="${CLOUDFLARED_TOKEN:-}"
fi

echo
echo "==> Cloudflared setup summary"
echo "Existing service: ${SERVICE_EXISTS}"
echo "Reinstall:        ${REINSTALL_CLOUDFLARED_SERVICE}"

if [ "${REINSTALL_CLOUDFLARED_SERVICE}" = "true" ]; then
  echo "Token:            provided"
else
  echo "Token:            not needed"
fi

echo
confirm_continue

echo "==> Installing/updating cloudflared..."

ARCH="$(dpkg --print-architecture)"

case "${ARCH}" in
  amd64)
    CLOUDFLARED_DEB_URL="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb"
    ;;
  arm64)
    CLOUDFLARED_DEB_URL="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64.deb"
    ;;
  *)
    echo "ERROR: Unsupported architecture: ${ARCH}"
    exit 1
    ;;
esac

TMP_DEB="$(mktemp /tmp/cloudflared.XXXXXX.deb)"
trap 'rm -f "${TMP_DEB}"' EXIT

curl -fsSL "${CLOUDFLARED_DEB_URL}" -o "${TMP_DEB}"
dpkg-deb --info "${TMP_DEB}" >/dev/null
apt-get install -y "${TMP_DEB}"
rm -f "${TMP_DEB}"

echo "==> cloudflared installed:"
cloudflared --version

if [ "${REINSTALL_CLOUDFLARED_SERVICE}" = "true" ]; then
  if [ "${SERVICE_EXISTS}" = "true" ]; then
    echo "==> Reinstalling cloudflared service..."

    systemctl stop cloudflared || true
    systemctl disable cloudflared || true
    cloudflared service uninstall || true
  else
    echo "==> Installing cloudflared service..."
  fi

  cloudflared service install "${CLOUDFLARED_TOKEN}"
  unset CLOUDFLARED_TOKEN
else
  echo "==> Keeping existing cloudflared service."
fi

echo "==> Enabling and starting cloudflared..."
systemctl enable cloudflared
systemctl restart cloudflared

echo
echo "==> cloudflared status:"
systemctl status cloudflared --no-pager || true

echo
echo "==> Cloudflared setup complete."
echo
echo "Next:"
echo "1. In Cloudflare Zero Trust, configure Public Hostnames."
echo "2. For Dokploy webhook-only exposure, point hostname to your local proxy later."
echo "3. You do not need to open ports 80, 443, or 8088 in UFW."
