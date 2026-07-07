#!/usr/bin/env bash
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  echo "ERROR: Run this script as root or with sudo."
  exit 1
fi

echo "==> Dokploy installer will be run from the official install endpoint."
echo "Review Dokploy docs before running this script on production systems."
echo
echo "IMPORTANT:"
echo "Dokploy exposes the dashboard on port 3000."
echo "This script will:"
echo "  1. Install Dokploy"
echo "  2. Advertise the Dokploy Docker subnet through Tailscale"
echo "  3. Add Docker-aware firewall rules to allow port 3000 via Tailscale only"
echo

read -r -p "Continue installing Dokploy? [y/N] " answer

case "${answer}" in
  y|Y|yes|YES) ;;
  *) echo "Aborted."; exit 0 ;;
esac

echo "==> Installing Dokploy..."
curl -sSL https://dokploy.com/install.sh | sh

echo
echo "==> Detecting Dokploy Docker network subnet..."

DOKPLOY_SUBNET="$(docker network inspect dokploy-network -f '{{range .IPAM.Config}}{{.Subnet}}{{end}}' 2>/dev/null || true)"

if [ -z "${DOKPLOY_SUBNET}" ]; then
  echo "WARNING: Could not detect dokploy-network subnet."
  echo "You can check it manually later with:"
  echo "  docker network inspect dokploy-network | grep Subnet"
else
  echo "Detected Dokploy subnet: ${DOKPLOY_SUBNET}"

  if command -v tailscale >/dev/null 2>&1; then
    echo
    echo "==> Advertising Dokploy Docker subnet through Tailscale..."
    tailscale up --ssh --advertise-routes="${DOKPLOY_SUBNET}" || {
      echo
      echo "WARNING: tailscale up failed."
      echo "You may need to run this manually:"
      echo "  sudo tailscale up --ssh --advertise-routes=${DOKPLOY_SUBNET}"
    }

    echo
    echo "IMPORTANT:"
    echo "Go to the Tailscale Admin Console and approve the advertised route:"
    echo "  ${DOKPLOY_SUBNET}"
  else
    echo "WARNING: tailscale command not found. Skipping subnet route advertisement."
  fi
fi

echo
echo "==> Locking Dokploy dashboard to Tailscale only..."

# Allow Dokploy dashboard through Tailscale
iptables -C DOCKER-USER -i tailscale0 -p tcp --dport 3000 -j ACCEPT 2>/dev/null || \
iptables -I DOCKER-USER 1 -i tailscale0 -p tcp --dport 3000 -j ACCEPT

# Block Dokploy dashboard from public/non-Tailscale interfaces
iptables -C DOCKER-USER -p tcp --dport 3000 -j DROP 2>/dev/null || \
iptables -I DOCKER-USER 2 -p tcp --dport 3000 -j DROP

echo
echo "==> Saving iptables rules..."

if command -v netfilter-persistent >/dev/null 2>&1; then
  netfilter-persistent save
else
  apt-get update
  DEBIAN_FRONTEND=noninteractive apt-get install -y iptables-persistent
  netfilter-persistent save
fi

echo
echo "==> Dokploy install command finished."
echo

if command -v tailscale >/dev/null 2>&1; then
  TAILSCALE_IP="$(tailscale ip -4 2>/dev/null || true)"
  if [ -n "${TAILSCALE_IP}" ]; then
    echo "Dokploy should be private via Tailscale:"
    echo "  http://${TAILSCALE_IP}:3000"
  fi
fi

echo
echo "Public access to port 3000 should now be blocked by DOCKER-USER."
echo "Still recommended: also block port 3000 in your VPS provider firewall."
