#!/usr/bin/env bash
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  echo "ERROR: Run this script as root."
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
ENV_FILE="${REPO_DIR}/.env"

if [ ! -f "${ENV_FILE}" ]; then
  echo "ERROR: .env file not found."
  echo "Create it first:"
  echo "  cp .env.example .env"
  echo "  nano .env"
  exit 1
fi

set -a
# shellcheck disable=SC1090
source "${ENV_FILE}"
set +a

VPS_USER="${VPS_USER:-}"
SSH_PUBLIC_KEY="${SSH_PUBLIC_KEY:-}"
SERVER_TIMEZONE="${SERVER_TIMEZONE:-UTC}"
REPO_NAME="${REPO_NAME:-vps-infra}"

if [ -z "${VPS_USER}" ]; then
  echo "ERROR: VPS_USER is required in .env"
  exit 1
fi

echo "==> Setting timezone to ${SERVER_TIMEZONE}..."
timedatectl set-timezone "${SERVER_TIMEZONE}"

echo "==> Updating system packages..."
apt update
apt upgrade -y

echo "==> Installing base packages..."
apt install -y \
  curl \
  wget \
  git \
  vim \
  nano \
  htop \
  unzip \
  rsync \
  ca-certificates \
  gnupg \
  lsb-release \
  ufw \
  software-properties-common \
  apt-transport-https \
  unattended-upgrades

echo "==> Enabling unattended-upgrades..."
systemctl enable unattended-upgrades
systemctl restart unattended-upgrades

echo "==> Creating sudo user: ${VPS_USER}..."

if id "${VPS_USER}" >/dev/null 2>&1; then
  echo "==> User ${VPS_USER} already exists. Skipping creation."
else
  adduser "${VPS_USER}"
fi

echo "==> Adding ${VPS_USER} to sudo group..."
usermod -aG sudo "${VPS_USER}"

if [ -n "${SSH_PUBLIC_KEY}" ]; then
  echo "==> Installing SSH public key for ${VPS_USER}..."

  USER_HOME="$(eval echo "~${VPS_USER}")"
  SSH_DIR="${USER_HOME}/.ssh"
  AUTH_KEYS="${SSH_DIR}/authorized_keys"

  mkdir -p "${SSH_DIR}"
  touch "${AUTH_KEYS}"

  if grep -qxF "${SSH_PUBLIC_KEY}" "${AUTH_KEYS}"; then
    echo "==> SSH key already exists. Skipping."
  else
    echo "${SSH_PUBLIC_KEY}" >> "${AUTH_KEYS}"
  fi

  chown -R "${VPS_USER}:${VPS_USER}" "${SSH_DIR}"
  chmod 700 "${SSH_DIR}"
  chmod 600 "${AUTH_KEYS}"
else
  echo "==> SSH_PUBLIC_KEY is empty. Skipping SSH key setup."
  echo "==> You can add it later using: ssh-copy-id ${VPS_USER}@SERVER_IP"
fi

echo "==> Copying repo to /home/${VPS_USER}/${REPO_NAME}..."

USER_REPO_DIR="/home/${VPS_USER}/${REPO_NAME}"

if [ "${REPO_DIR}" != "${USER_REPO_DIR}" ]; then
  mkdir -p "${USER_REPO_DIR}"
  rsync -a \
    --exclude ".git" \
    --exclude ".env" \
    "${REPO_DIR}/" "${USER_REPO_DIR}/"

  cp "${ENV_FILE}" "${USER_REPO_DIR}/.env"

  chown -R "${VPS_USER}:${VPS_USER}" "${USER_REPO_DIR}"
else
  echo "==> Repo already inside user home. Skipping copy."
fi

echo "==> Base setup complete."
echo
echo "Next steps:"
echo "1. From your laptop, test:"
echo "   ssh ${VPS_USER}@SERVER_IP"
echo
echo "2. Then run:"
echo "   cd ~/${REPO_NAME}"
echo "   sudo bash scripts/01-docker.sh"
