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
else
  echo "ERROR: .env file not found at ${ENV_FILE}"
  echo "Create it from .env.example first:"
  echo "  cp .env.example .env"
  exit 1
fi

VPS_USER="${VPS_USER:-}"

if [ -z "${VPS_USER}" ]; then
  echo "ERROR: VPS_USER is required in .env"
  exit 1
fi

if [ "$(id -u)" -ne 0 ]; then
  echo "ERROR: Run this script as root or with sudo."
  exit 1
fi

echo "==> Removing conflicting Docker packages..."
apt remove -y docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc || true

echo "==> Installing Docker repository dependencies..."
apt update
apt install -y ca-certificates curl gnupg

echo "==> Adding Docker GPG key..."
install -m 0755 -d /etc/apt/keyrings

if [ -f /etc/apt/keyrings/docker.gpg ]; then
  rm -f /etc/apt/keyrings/docker.gpg
fi

curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
  | gpg --dearmor -o /etc/apt/keyrings/docker.gpg

chmod a+r /etc/apt/keyrings/docker.gpg

echo "==> Adding Docker apt repository..."
. /etc/os-release

UBUNTU_CODENAME="${UBUNTU_CODENAME:-$VERSION_CODENAME}"

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu ${UBUNTU_CODENAME} stable" \
  > /etc/apt/sources.list.d/docker.list

echo "==> Installing Docker Engine and Compose plugin..."
apt update
apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

echo "==> Enabling Docker service..."
systemctl enable docker
systemctl start docker

echo "==> Adding user '${VPS_USER}' to docker group..."
usermod -aG docker "${VPS_USER}"

echo "==> Docker installed."
echo
echo "Log out and log back in, then run:"
echo "  docker version"
echo "  docker compose version"
echo "  docker run hello-world"
