#!/usr/bin/env bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a

if [ "$(id -u)" -ne 0 ]; then
  echo "ERROR: Run this script as root."
  exit 1
fi

prompt_required() {
  local var_name="$1"
  local prompt_text="$2"
  local value="${!var_name:-}"

  while [ -z "${value}" ]; do
    read -r -p "${prompt_text}: " value </dev/tty

    if [ -z "${value}" ]; then
      echo "ERROR: ${var_name} is required."
    fi
  done

  printf -v "${var_name}" '%s' "${value}"
  export "${var_name}"
}

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

validate_username() {
  local username="$1"

  if [ "${username}" = "root" ]; then
    echo "ERROR: VPS_USER cannot be root."
    exit 1
  fi

  if ! [[ "${username}" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]; then
    echo "ERROR: Invalid VPS username: ${username}"
    echo "Use lowercase letters, numbers, underscore, or hyphen."
    echo "Must start with a lowercase letter or underscore."
    echo "Maximum length: 32 characters."
    exit 1
  fi
}

validate_timezone() {
  local timezone="$1"

  if timedatectl list-timezones | grep -qx "${timezone}"; then
    return 0
  fi

  echo "ERROR: Invalid timezone: ${timezone}"
  echo "Example valid values:"
  echo "  UTC"
  echo "  America/Los_Angeles"
  echo "  Europe/London"
  echo "  Asia/Dubai"
  exit 1
}

validate_ssh_key() {
  local key="$1"

  if [ -z "${key}" ]; then
    return 0
  fi

  case "${key}" in
    ssh-rsa\ *|ssh-ed25519\ *|ecdsa-sha2-nistp256\ *|ecdsa-sha2-nistp384\ *|ecdsa-sha2-nistp521\ *)
      ;;
    *)
      echo "ERROR: SSH_PUBLIC_KEY does not look like a valid SSH public key."
      echo "Expected it to start with ssh-ed25519, ssh-rsa, or ecdsa-sha2-*."
      exit 1
      ;;
  esac
}

prompt_required "VPS_USER" "Enter VPS username"
prompt_optional "SERVER_TIMEZONE" "Enter server timezone" "UTC"

if [ -z "${SSH_PUBLIC_KEY:-}" ]; then
  echo
  echo "SSH public key is optional but recommended."
  echo "You can generate one on your laptop with:"
  echo "  ssh-keygen -t ed25519 -C \"your_email@example.com\""
  echo
  echo "Then copy the public key, usually:"
  echo "  ~/.ssh/id_ed25519.pub"
  echo
  read -r -p "Paste SSH public key, or press Enter to skip: " SSH_PUBLIC_KEY </dev/tty
fi

export SSH_PUBLIC_KEY

validate_username "${VPS_USER}"
validate_timezone "${SERVER_TIMEZONE}"
validate_ssh_key "${SSH_PUBLIC_KEY}"

echo
echo "==> Setup summary"
echo "User:       ${VPS_USER}"
echo "Timezone:   ${SERVER_TIMEZONE}"

if [ -n "${SSH_PUBLIC_KEY}" ]; then
  echo "SSH key:    yes"
else
  echo "SSH key:    no"
fi

echo
confirm_continue

echo "==> Setting timezone to ${SERVER_TIMEZONE}..."
timedatectl set-timezone "${SERVER_TIMEZONE}"

echo "==> Updating system packages..."
apt-get update
apt-get --fix-broken install -y
apt-get upgrade -y || {
  echo "==> Upgrade failed, attempting to work around package conflicts..."
  apt-mark hold fwupd libfwupd2 libfwupdplugin5 2>/dev/null || true
  apt-get upgrade -y
}

echo "==> Installing base packages..."
apt-get install -y \
  sudo \
  curl \
  wget \
  git \
  vim \
  nano \
  htop \
  unzip \
  ca-certificates \
  gnupg \
  lsb-release \
  ufw \
  software-properties-common \
  apt-transport-https \
  unattended-upgrades

echo "==> Enabling unattended-upgrades..."
systemctl enable unattended-upgrades

if systemctl is-active --quiet unattended-upgrades; then
  systemctl restart unattended-upgrades
else
  systemctl start unattended-upgrades
fi

echo "==> Ensuring sudo user exists: ${VPS_USER}..."

if id "${VPS_USER}" >/dev/null 2>&1; then
  echo "==> User ${VPS_USER} already exists. Skipping creation."
else
  adduser --disabled-password --gecos "" "${VPS_USER}"

  while true; do
    read -r -s -p "Enter password for ${VPS_USER}: " VPS_PASSWORD </dev/tty
    echo >&2
    read -r -s -p "Confirm password: " VPS_PASSWORD_CONFIRM </dev/tty
    echo >&2

    if [ "${#VPS_PASSWORD}" -lt 8 ]; then
      echo "ERROR: Password must be at least 8 characters." >&2
    elif [ "${VPS_PASSWORD}" != "${VPS_PASSWORD_CONFIRM}" ]; then
      echo "ERROR: Passwords do not match." >&2
    else
      break
    fi
  done

  echo "${VPS_USER}:${VPS_PASSWORD}" | chpasswd
  unset VPS_PASSWORD VPS_PASSWORD_CONFIRM
fi

echo "==> Ensuring ${VPS_USER} is in sudo group..."
usermod -aG sudo "${VPS_USER}"

USER_HOME="$(getent passwd "${VPS_USER}" | cut -d: -f6)"

if [ -z "${USER_HOME}" ] || [ ! -d "${USER_HOME}" ]; then
  echo "ERROR: Could not determine home directory for ${VPS_USER}."
  exit 1
fi

if [ -n "${SSH_PUBLIC_KEY}" ]; then
  echo "==> Ensuring SSH public key is installed for ${VPS_USER}..."

  SSH_DIR="${USER_HOME}/.ssh"
  AUTH_KEYS="${SSH_DIR}/authorized_keys"

  mkdir -p "${SSH_DIR}"
  touch "${AUTH_KEYS}"

  if grep -qxF "${SSH_PUBLIC_KEY}" "${AUTH_KEYS}"; then
    echo "==> SSH key already exists. Skipping."
  else
    echo "${SSH_PUBLIC_KEY}" >> "${AUTH_KEYS}"
    echo "==> SSH key added."
  fi

  chown -R "${VPS_USER}:${VPS_USER}" "${SSH_DIR}"
  chmod 700 "${SSH_DIR}"
  chmod 600 "${AUTH_KEYS}"
else
  echo "==> SSH_PUBLIC_KEY is empty. Skipping SSH key setup."
  echo "==> You can add it later using:"
  echo "    ssh-copy-id ${VPS_USER}@SERVER_IP"
fi

echo
echo "==> Base setup complete."
echo
echo "Next steps:"
echo "1. From your laptop, test:"
echo "   ssh ${VPS_USER}@SERVER_IP"
echo
echo "2. Then continue with your next setup script."
