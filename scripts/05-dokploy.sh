#!/usr/bin/env bash
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  echo "ERROR: Run this script as root or with sudo."
  exit 1
fi

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
    tailscale set --ssh --advertise-routes="${DOKPLOY_SUBNET}" || {
      echo
      echo "WARNING: tailscale set failed."
      echo "You may need to run this manually:"
      echo "  sudo tailscale set --ssh --advertise-routes=${DOKPLOY_SUBNET}"
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
echo "==> Recreating Dokploy Traefik with localhost-only bindings..."

docker stop dokploy-traefik 2>/dev/null || true
docker rm dokploy-traefik 2>/dev/null || true

docker run -d \
  --name dokploy-traefik \
  --restart always \
  -v /etc/dokploy/traefik/traefik.yml:/etc/traefik/traefik.yml \
  -v /etc/dokploy/traefik/dynamic:/etc/dokploy/traefik/dynamic \
  -v /var/run/docker.sock:/var/run/docker.sock:ro \
  -p 127.0.0.1:80:80/tcp \
  -p 127.0.0.1:443:443/tcp \
  -p 127.0.0.1:443:443/udp \
  traefik:v3.6.7

docker network connect dokploy-network dokploy-traefik 2>/dev/null || true

echo
echo "==> Restricting Dokploy dashboard port 3000 to Tailscale only..."

if ! iptables -nL DOCKER-USER >/dev/null 2>&1; then
  echo "WARNING: DOCKER-USER chain not found. Docker may not be running correctly."
else
  # Remove older duplicate copies of these exact rules if present.
  while iptables -C DOCKER-USER -i tailscale0 -p tcp --dport 3000 -j ACCEPT 2>/dev/null; do
    iptables -D DOCKER-USER -i tailscale0 -p tcp --dport 3000 -j ACCEPT
  done

  while iptables -C DOCKER-USER -p tcp --dport 3000 -j DROP 2>/dev/null; do
    iptables -D DOCKER-USER -p tcp --dport 3000 -j DROP
  done

  # Order matters: allow Tailscale first, then drop everyone else.
  iptables -I DOCKER-USER 1 -i tailscale0 -p tcp --dport 3000 -j ACCEPT
  iptables -I DOCKER-USER 2 -p tcp --dport 3000 -j DROP

  echo "Applied DOCKER-USER rules:"
  iptables -S DOCKER-USER | grep -- '--dport 3000' || true
fi

echo
echo "==> Saving iptables rules for persistence..."

if command -v apt-get >/dev/null 2>&1; then
  export DEBIAN_FRONTEND=noninteractive

  if ! command -v netfilter-persistent >/dev/null 2>&1; then
    apt-get update
    apt-get install -y iptables-persistent
  fi

  if command -v netfilter-persistent >/dev/null 2>&1; then
    netfilter-persistent save
    echo "Saved iptables rules with netfilter-persistent."
  else
    echo "WARNING: netfilter-persistent not found. iptables rules may not survive reboot."
  fi
else
  echo "WARNING: apt-get not found. Skipping iptables-persistent install."
  echo "iptables rules are active now but may not survive reboot."
fi

if command -v tailscale >/dev/null 2>&1; then
  TAILSCALE_IP="$(tailscale ip -4 2>/dev/null || true)"
  if [ -n "${TAILSCALE_IP}" ]; then
    echo
    echo "Dokploy should be private via Tailscale:"
    echo "  http://${TAILSCALE_IP}:3000"
  fi
fi

echo
echo "Dokploy dashboard port 3000 is now allowed only via tailscale0 using DOCKER-USER rules."
echo "Public access to port 3000 should be blocked:"
echo "  http://PUBLIC_IP:3000"
echo
echo "Traefik HTTP/HTTPS is bound to localhost only:"
echo "  http://127.0.0.1"
echo "  https://127.0.0.1"
echo
echo "Use cloudflared with:"
echo "  http://127.0.0.1:80"
echo
echo "Recommended: also block public inbound 3000 in your VPS provider firewall."
