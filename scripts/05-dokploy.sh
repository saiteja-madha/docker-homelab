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
echo "This script will add Docker-aware firewall rules to allow port 3000 via Tailscale only."
echo

read -r -p "Continue installing Dokploy? [y/N] " answer

case "${answer}" in
  y|Y|yes|YES) ;;
  *) echo "Aborted."; exit 0 ;;
esac

echo "==> Installing Dokploy..."
curl -sSL https://dokploy.com/install.sh | sh

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
echo "Dokploy should be private via Tailscale:"
echo "  http://$(tailscale ip -4):3000"
echo
echo "Public access to port 3000 should now be blocked."
echo "Still recommended: also block port 3000 in your VPS provider firewall."
