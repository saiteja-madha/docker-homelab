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

if command -v tailscale >/dev/null 2>&1; then
  TAILSCALE_IP="$(tailscale ip -4 2>/dev/null || true)"
  if [ -n "${TAILSCALE_IP}" ]; then
    echo "Dokploy should be private via Tailscale:"
    echo "  http://${TAILSCALE_IP}:3000"
  fi
fi

echo
echo "Dokploy dashboard is still available on port 3000 unless blocked elsewhere."
echo "Traefik HTTP/HTTPS is now bound to localhost only:"
echo "  http://127.0.0.1"
echo "  https://127.0.0.1"
echo
echo "Use cloudflared with:"
echo "  http://127.0.0.1:80"
echo
echo "Recommended: block public inbound 3000 in your VPS provider firewall."
