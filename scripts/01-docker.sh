#!/usr/bin/env bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a

if [ "$(id -u)" -ne 0 ]; then
  echo "ERROR: Run this script as root or with sudo."
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

validate_username() {
  local username="$1"

  if ! [[ "${username}" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]; then
    echo "ERROR: Invalid VPS username: ${username}"
    echo "Use lowercase letters, numbers, underscore, or hyphen."
    echo "Must start with a lowercase letter or underscore."
    echo "Maximum length: 32 characters."
    exit 1
  fi
}

prompt_required "VPS_USER" "Enter VPS username to add to docker group"
validate_username "${VPS_USER}"

if ! id "${VPS_USER}" >/dev/null 2>&1; then
  echo "ERROR: User '${VPS_USER}' does not exist."
  echo "Run the base setup script first, or create the user before installing Docker."
  exit 1
fi

if [ ! -r /etc/os-release ]; then
  echo "ERROR: /etc/os-release not found."
  exit 1
fi

. /etc/os-release

if [ "${ID:-}" != "ubuntu" ]; then
  echo "ERROR: This script is intended for Ubuntu only."
  echo "Detected OS: ${ID:-unknown}"
  exit 1
fi

UBUNTU_CODENAME="${UBUNTU_CODENAME:-${VERSION_CODENAME:-}}"

if [ -z "${UBUNTU_CODENAME}" ]; then
  echo "ERROR: Could not determine Ubuntu codename."
  exit 1
fi

echo "==> Docker setup summary"
echo "User:             ${VPS_USER}"
echo "Ubuntu codename:  ${UBUNTU_CODENAME}"
echo

if [ "${ASSUME_YES:-false}" != "true" ]; then
  read -r -p "Continue? [y/N]: " CONFIRM </dev/tty

  case "${CONFIRM}" in
    y|Y|yes|YES)
      ;;
    *)
      echo "Aborted."
      exit 0
      ;;
  esac
fi

echo "==> Removing conflicting Docker packages..."
apt-get remove -y docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc || true

echo "==> Installing Docker repository dependencies..."
apt-get update
apt-get install -y ca-certificates curl gnupg

echo "==> Adding Docker GPG key..."
install -m 0755 -d /etc/apt/keyrings

curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
  | gpg --dearmor -o /etc/apt/keyrings/docker.gpg.tmp

mv /etc/apt/keyrings/docker.gpg.tmp /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

echo "==> Adding Docker apt repository..."
cat > /etc/apt/sources.list.d/docker.list <<EOF
deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu ${UBUNTU_CODENAME} stable
EOF

echo "==> Installing Docker Engine and Compose plugin..."
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

echo "==> Enabling Docker service..."
systemctl enable docker
systemctl start docker

echo "==> Ensuring docker group exists..."
getent group docker >/dev/null 2>&1 || groupadd docker

echo "==> Adding user '${VPS_USER}' to docker group..."
usermod -aG docker "${VPS_USER}"

echo
echo "==> Docker installed."
echo
echo "Installed versions:"
docker --version || true
docker compose version || true
echo
echo "Important:"
echo "Log out and log back in for docker group membership to take effect."
echo
echo "Then run:"
echo "  docker version"
echo "  docker compose version"
echo "  docker run hello-world"
