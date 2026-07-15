# Provisioning

This guide targets a fresh Ubuntu 24.04 LTS VPS. Use the provider console as a
fallback while changing SSH, Tailscale, or firewall configuration.

## Before starting

Prepare these items outside the server:

- VPS provider console access
- an Ed25519 SSH public key
- Tailscale account access or a short-lived, single-use auth key
- Cloudflare account, domain, and tunnel token
- S3-compatible bucket and restricted credentials for Dokploy backups
- password-manager entries for all recovery credentials

Clone and inspect the repository. Do not pipe these scripts from a URL into a
root shell.

```bash
apt-get update
apt-get install -y ca-certificates git
git clone https://github.com/saiteja-madha/docker-homelab.git
cd docker-homelab
git status
```

Run the reviewed commit. For a recovery, record the commit hash in the recovery
log:

```bash
git rev-parse HEAD
```

## 1. Base operating system

```bash
sudo bash scripts/00-base.sh
```

The script updates packages, installs the base administration tools, enables
unattended upgrades, creates a sudo user, and installs an optional SSH key.

Before continuing, open a second terminal and verify the new account:

```bash
ssh VPS_USER@SERVER_IP
sudo -v
```

The script does not disable password authentication or root SSH automatically.
Make those changes only after key and provider-console access are proven; see
[Security](security.md#ssh-hardening).

## 2. Docker

```bash
sudo VPS_USER=your-user bash scripts/01-docker.sh
```

Log out and back in, then verify:

```bash
docker version
docker compose version
docker run --rm hello-world
```

The Docker group is root-equivalent. Only trusted administrators belong in it.

## 3. Tailscale

```bash
sudo bash scripts/02-tailscale.sh
```

The auth-key prompt is hidden. Prefer interactive authentication or a reusable
key with the shortest practical lifetime. Verify from a second machine:

```bash
tailscale status
tailscale ip -4
tailscale ssh VPS_USER@TAILSCALE_HOSTNAME
```

Reruns keep existing Tailscale preferences unless reconfiguration is explicitly
approved.

## 4. Cockpit

```bash
sudo bash scripts/03-cockpit.sh
```

Cockpit binds to the detected Tailscale address. The script fails closed if
Tailscale is unavailable. `ALLOW_PUBLIC_COCKPIT=true` is an emergency override,
not a normal configuration.

Verify at `https://TAILSCALE_IP:9090`. A local certificate warning is expected
unless a trusted certificate has been installed.

## 5. Firewall

```bash
sudo bash scripts/04-ufw.sh
```

When Tailscale is active, public SSH is disabled by default and inbound traffic
on `tailscale0` is allowed. Without Tailscale, public SSH remains allowed to
avoid lockout. Existing UFW rules are retained unless `RESET_UFW=true` is set.

Review before closing the provider console:

```bash
sudo ufw status verbose
ss -lntup
```

Also configure the provider firewall. Do not rely on UFW alone for Docker
published ports.

## 6. Dokploy

The official Dokploy installer is downloaded to a temporary file before it is
executed. Pin a version when reproducibility matters:

```bash
sudo DOKPLOY_VERSION=vX.Y.Z bash scripts/05-dokploy.sh
```

For a normal fresh install where the current stable version is acceptable:

```bash
sudo bash scripts/05-dokploy.sh
```

The script:

- requires Docker and an active Tailscale interface;
- installs or updates Dokploy using its official installer;
- preserves the installer-selected Traefik image while recreating Traefik with
  loopback-only HTTP/HTTPS bindings for Cloudflare Tunnel;
- restricts public access to dashboard port `3000` using `DOCKER-USER` rules;
- persists those rules with `netfilter-persistent`.

Direct Docker-subnet advertisement is disabled by default. Enable it only when
clients need direct access to container addresses:

```bash
sudo ADVERTISE_DOKPLOY_SUBNET=true bash scripts/05-dokploy.sh
```

Open `http://TAILSCALE_IP:3000`, create the initial administrator, enable MFA,
and configure the backup destinations before adding applications.

## 7. Cloudflare Tunnel

```bash
sudo bash scripts/06-cloudflared.sh
```

The tunnel token prompt is hidden. Configure public application hostnames to
`http://127.0.0.1:80`. Configure a separate webhook-only hostname to
`http://127.0.0.1:8088` after deploying the proxy in Dokploy.

Do not open ports `80`, `443`, or `8088` in UFW for a locally managed tunnel.

## 8. GitHub webhook bridge

In the Tailscale-only Dokploy UI, create a Compose service connected to this
GitHub repository and select `tools/dokploy-webhook-proxy/docker-compose.yml`.
Deploy it manually for the first time; the webhook cannot trigger its own initial
deployment.

Point a dedicated Cloudflare Tunnel hostname at `http://127.0.0.1:8088`, then
configure the GitHub webhook URL as:

```text
https://deploy.example.com/api/deploy/github
```

Test a GitHub delivery and confirm a valid signature is accepted while a request
without the configured webhook secret is rejected. See the proxy's
[tool-specific guide](../tools/dokploy-webhook-proxy/README.md).

## Optional developer tools

Run as the intended non-root user:

```bash
bash scripts/07-dev-tools.sh
```

Go downloads are checked against the SHA-256 value from Go's release metadata.
The NVM installer is version-pinned but still executes upstream code; review it
before use on a sensitive host.

## Completion checklist

- SSH and Cockpit work through Tailscale.
- Provider firewall exposes no admin ports.
- `PUBLIC_IP:3000` is unreachable.
- Public application hostnames work through Cloudflare Tunnel.
- The webhook hostname exposes only the deploy endpoint.
- Dokploy administrator MFA is enabled.
- Control-plane, database, and volume backups have successful test objects in S3.
- A restore test date and recovery credentials are recorded off-server.
