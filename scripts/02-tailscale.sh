#!/usr/bin/env bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

if [ "$(id -u)" -ne 0 ]; then
  echo "ERROR: Run this script as root or with sudo."
  exit 1
fi

prompt_optional_empty() {
  local var_name="$1"
  local prompt_text="$2"
  local value="${!var_name:-}"

  if [ -z "${value}" ]; then
    read -r -p "${prompt_text}: " value </dev/tty
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

echo "Tailscale auth key is optional."
echo "Leave it empty if you want to authenticate interactively in the browser."
prompt_optional_empty "TAILSCALE_AUTH_KEY" "Enter Tailscale auth key, or press Enter to skip"

echo
echo "Tailscale hostname is optional."
prompt_optional_empty "TAILSCALE_HOSTNAME" "Enter Tailscale hostname, or press Enter to skip"

echo
echo "==> Tailscale setup summary"

if [ -n "${TAILSCALE_AUTH_KEY}" ]; then
  echo "Auth key:   yes"
else
  echo "Auth key:   no"
fi

if [ -n "${TAILSCALE_HOSTNAME}" ]; then
  echo "Hostname:   ${TAILSCALE_HOSTNAME}"
else
  echo "Hostname:   default"
fi

echo
confirm_continue

if command -v tailscale >/dev/null 2>&1; then
  echo "==> Tailscale is already installed. Skipping installer."
else
  echo "==> Installing Tailscale..."
  curl -fsSL https://tailscale.com/install.sh | sh
fi

echo "==> Enabling tailscaled..."
systemctl enable tailscaled
systemctl start tailscaled

UP_ARGS=(--ssh)

if [ -n "${TAILSCALE_HOSTNAME}" ]; then
  UP_ARGS+=(--hostname "${TAILSCALE_HOSTNAME}")
fi

if tailscale status >/dev/null 2>&1; then
  echo "==> Tailscale is already authenticated."

  RECONFIGURE_TAILSCALE="${RECONFIGURE_TAILSCALE:-}"

  if [ -z "${RECONFIGURE_TAILSCALE}" ]; then
    echo
    echo "Reconfiguring Tailscale can overwrite existing settings such as:"
    echo "  --advertise-routes"
    echo "  --advertise-exit-node"
    echo "  --accept-routes"
    echo
    read -r -p "Reconfigure Tailscale with this script's settings? [y/N]: " RECONFIGURE_TAILSCALE </dev/tty
  fi

  if is_yes "${RECONFIGURE_TAILSCALE}"; then
    echo "==> Reconfiguring Tailscale with --reset..."
    tailscale up --reset "${UP_ARGS[@]}"
  else
    echo "==> Keeping existing Tailscale settings."
    echo "==> Skipping tailscale up."
  fi
else
  if [ -n "${TAILSCALE_AUTH_KEY}" ]; then
    echo "==> Bringing Tailscale up using auth key with SSH enabled..."
    tailscale up --auth-key "${TAILSCALE_AUTH_KEY}" "${UP_ARGS[@]}"
  else
    echo "==> Bringing Tailscale up interactively with SSH enabled..."
    tailscale up "${UP_ARGS[@]}"
  fi
fi

echo
echo "==> Tailscale status:"
tailscale status || true

echo
echo "Tailscale IPv4:"
tailscale ip -4 || true

echo
echo "Tailscale SSH status:"
if tailscale status --json 2>/dev/null | grep -q '"TailscaleSSH"[[:space:]]*:[[:space:]]*true'; then
  echo "Tailscale SSH appears to be enabled for this machine."
else
  echo "Could not confirm Tailscale SSH from local status output."
  echo "If needed, run:"
  echo "  sudo tailscale up --ssh"
  echo
  echo "If you have advertised routes, include them too, for example:"
  echo "  sudo tailscale up --ssh --advertise-routes=10.0.1.0/24"
fi
