#!/usr/bin/env bash
set -euo pipefail
umask 027

if [ "$(id -u)" -ne 0 ]; then
  echo "ERROR: Run this script as root or with sudo."
  exit 1
fi

if ! command -v docker >/dev/null 2>&1; then
  echo "ERROR: Docker is required. Run scripts/01-docker.sh first."
  exit 1
fi

if ! command -v tailscale >/dev/null 2>&1 || ! ip link show tailscale0 >/dev/null 2>&1; then
  echo "ERROR: An active Tailscale interface is required before installing Dokploy."
  echo "Run scripts/02-tailscale.sh first."
  exit 1
fi

if [ -n "${DOKPLOY_VERSION:-}" ] &&
  ! [[ "${DOKPLOY_VERSION}" =~ ^(latest|canary|v[0-9]+\.[0-9]+\.[0-9]+([.-][A-Za-z0-9.-]+)?)$ ]]; then
  echo "ERROR: Invalid DOKPLOY_VERSION: ${DOKPLOY_VERSION}"
  echo "Use latest, canary, or a release such as v0.29.0."
  exit 1
fi

if [ "${ASSUME_YES:-false}" != "true" ]; then
  echo "This runs Dokploy's official installer and changes Docker networking."
  read -r -p "Continue? [y/N]: " CONFIRM </dev/tty
  case "${CONFIRM}" in
    y|Y|yes|YES) ;;
    *) echo "Aborted."; exit 0 ;;
  esac
fi

echo "==> Installing Dokploy..."
INSTALLER="$(mktemp /tmp/dokploy-install.XXXXXX.sh)"
trap 'rm -f "${INSTALLER}"' EXIT
curl -fsSL https://dokploy.com/install.sh -o "${INSTALLER}"
chmod 0700 "${INSTALLER}"

if [ -n "${DOKPLOY_VERSION:-}" ]; then
  echo "==> Requested Dokploy version: ${DOKPLOY_VERSION}"
fi

sh "${INSTALLER}"

echo
echo "==> Detecting Dokploy Docker network subnet..."

DOKPLOY_SUBNET="$(docker network inspect dokploy-network -f '{{range .IPAM.Config}}{{.Subnet}}{{end}}' 2>/dev/null || true)"

if [ -z "${DOKPLOY_SUBNET}" ]; then
  echo "WARNING: Could not detect dokploy-network subnet."
  echo "You can check it manually later with:"
  echo "  docker network inspect dokploy-network | grep Subnet"
else
  echo "Detected Dokploy subnet: ${DOKPLOY_SUBNET}"

  case "${ADVERTISE_DOKPLOY_SUBNET:-false}" in
    true|TRUE|yes|YES|y|Y|1)
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
      ;;
    false|FALSE|no|NO|n|N|0)
      echo "==> Not advertising the Dokploy subnet (secure default)."
      echo "Set ADVERTISE_DOKPLOY_SUBNET=true only if Tailscale clients need direct container-subnet access."
      ;;
    *)
      echo "ERROR: ADVERTISE_DOKPLOY_SUBNET must be true or false."
      exit 1
      ;;
  esac
fi

echo
echo "==> Recreating Dokploy Traefik with localhost-only bindings..."

TRAEFIK_IMAGE="$(docker inspect --format '{{.Config.Image}}' dokploy-traefik 2>/dev/null || true)"

if [ -z "${TRAEFIK_IMAGE}" ]; then
  echo "ERROR: Could not determine the image used by dokploy-traefik."
  echo "Refusing to replace the container with a guessed or hard-coded image."
  exit 1
fi

if [ ! -f /etc/dokploy/traefik/traefik.yml ] || [ ! -d /etc/dokploy/traefik/dynamic ]; then
  echo "ERROR: Dokploy Traefik configuration is incomplete under /etc/dokploy/traefik."
  echo "Refusing to remove the running Traefik container."
  exit 1
fi

if ! docker image inspect "${TRAEFIK_IMAGE}" >/dev/null 2>&1; then
  echo "ERROR: Installed Traefik image ${TRAEFIK_IMAGE} is unavailable locally."
  echo "Refusing to remove the running Traefik container."
  exit 1
fi

echo "==> Preserving installed Traefik image: ${TRAEFIK_IMAGE}"

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
  "${TRAEFIK_IMAGE}"

docker network connect dokploy-network dokploy-traefik 2>/dev/null || true

echo
echo "==> Restricting Dokploy dashboard port 3000 to Tailscale only..."

PUBLIC_INTERFACE="$(ip route show default 0.0.0.0/0 | awk 'NR == 1 {print $5}')"

if [ -z "${PUBLIC_INTERFACE}" ]; then
  echo "ERROR: Could not detect the public/default network interface."
  echo "Refusing to claim the Dokploy dashboard is private."
  exit 1
elif ! iptables -nL DOCKER-USER >/dev/null 2>&1; then
  echo "ERROR: DOCKER-USER chain not found. Docker may not be running correctly."
  exit 1
else
  # Remove older duplicate copies of these exact rules if present.
  while iptables -C DOCKER-USER -i tailscale0 -p tcp --dport 3000 -j ACCEPT 2>/dev/null; do
    iptables -D DOCKER-USER -i tailscale0 -p tcp --dport 3000 -j ACCEPT
  done

  # Remove the legacy broad rule, which could block unrelated containers using port 3000.
  while iptables -C DOCKER-USER -p tcp --dport 3000 -j DROP 2>/dev/null; do
    iptables -D DOCKER-USER -p tcp --dport 3000 -j DROP
  done

  while iptables -C DOCKER-USER -i "${PUBLIC_INTERFACE}" -p tcp --dport 3000 -j DROP 2>/dev/null; do
    iptables -D DOCKER-USER -i "${PUBLIC_INTERFACE}" -p tcp --dport 3000 -j DROP
  done

  # Order matters: allow Tailscale first, then drop everyone else.
  iptables -I DOCKER-USER 1 -i tailscale0 -p tcp --dport 3000 -j ACCEPT
  iptables -I DOCKER-USER 2 -i "${PUBLIC_INTERFACE}" -p tcp --dport 3000 -j DROP

  iptables -C DOCKER-USER -i tailscale0 -p tcp --dport 3000 -j ACCEPT
  iptables -C DOCKER-USER -i "${PUBLIC_INTERFACE}" -p tcp --dport 3000 -j DROP

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
