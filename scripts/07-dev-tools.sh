#!/usr/bin/env bash
set -euo pipefail
umask 027

if [ "$(id -u)" -eq 0 ]; then
  echo "ERROR: Run this optional script as the intended non-root user."
  exit 1
fi

INSTALL_GO="${INSTALL_GO:-}"
INSTALL_NVM_PNPM="${INSTALL_NVM_PNPM:-}"

if [ -z "${INSTALL_GO}" ]; then
  read -r -p "Install Go? [y/N]: " INSTALL_GO </dev/tty
fi

if [ -z "${INSTALL_NVM_PNPM}" ]; then
  read -r -p "Install NVM, Node.js LTS, and pnpm? [y/N]: " INSTALL_NVM_PNPM </dev/tty
fi

if [[ ! "${INSTALL_GO}" =~ ^[yY] ]] && [[ ! "${INSTALL_NVM_PNPM}" =~ ^[yY] ]]; then
  echo "Nothing selected. Aborted."
  exit 0
fi

sudo apt update

if [[ "${INSTALL_GO}" =~ ^[yY] ]]; then
  echo
  echo "==> Installing Go..."

  sudo apt install -y curl jq

  ARCH="$(dpkg --print-architecture)"
  GO_METADATA="$(mktemp /tmp/go-downloads.XXXXXX.json)"
  curl -fsSL 'https://go.dev/dl/?mode=json' -o "${GO_METADATA}"
  VERSION="$(jq -r 'map(select(.stable))[0].version' "${GO_METADATA}")"
  GO_FILE="${VERSION}.linux-${ARCH}.tar.gz"
  GO_SHA256="$(jq -r --arg file "${GO_FILE}" 'map(select(.stable))[0].files[] | select(.filename == $file) | .sha256' "${GO_METADATA}")"
  rm -f "${GO_METADATA}"

  if [ -z "${VERSION}" ] || [ -z "${GO_SHA256}" ] || [ "${GO_SHA256}" = "null" ]; then
    echo "ERROR: Could not resolve a verified Go download for architecture ${ARCH}."
    exit 1
  fi

  GO_ARCHIVE="$(mktemp "/tmp/${GO_FILE}.XXXXXX")"
  curl -fsSL "https://go.dev/dl/${GO_FILE}" -o "${GO_ARCHIVE}"
  echo "${GO_SHA256}  ${GO_ARCHIVE}" | sha256sum --check --status

  sudo rm -rf /usr/local/go
  sudo tar -C /usr/local -xzf "${GO_ARCHIVE}"
  rm -f "${GO_ARCHIVE}"

  grep -qxF 'export PATH="/usr/local/go/bin:$HOME/go/bin:$PATH"' ~/.bashrc || \
    echo 'export PATH="/usr/local/go/bin:$HOME/go/bin:$PATH"' >> ~/.bashrc

  export PATH="/usr/local/go/bin:$HOME/go/bin:$PATH"

  echo "==> Go ${VERSION} installed."
fi

if [[ "${INSTALL_NVM_PNPM}" =~ ^[yY] ]]; then
  echo
  echo "==> Installing NVM, Node.js LTS, and pnpm..."

  sudo apt install -y curl ca-certificates

  NVM_VERSION="${NVM_VERSION:-v0.40.3}"

  if ! [[ "${NVM_VERSION}" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "ERROR: Invalid NVM_VERSION: ${NVM_VERSION}"
    exit 1
  fi

  NVM_INSTALLER="$(mktemp /tmp/nvm-install.XXXXXX.sh)"
  curl -fsSL "https://raw.githubusercontent.com/nvm-sh/nvm/${NVM_VERSION}/install.sh" -o "${NVM_INSTALLER}"
  bash "${NVM_INSTALLER}"
  rm -f "${NVM_INSTALLER}"

  export NVM_DIR="$HOME/.nvm"
  [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"

  nvm install --lts
  nvm alias default 'lts/*'
  nvm use --lts

  npm install --global corepack@latest
  corepack enable pnpm
  corepack install --global pnpm@latest

  echo "==> NVM, Node.js LTS, and pnpm installed."
fi

echo
echo "==> Dev tools setup complete."
