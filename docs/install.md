# VPS Install Guide

This guide assumes a fresh Ubuntu VPS.

## Recommended Approach

Run each setup script directly from its raw GitHub URL. Replace `<URL>` with the script's raw URL:

```bash
sudo bash -c "$(curl -fsSL <URL>)"
```

The URL format is:
```
https://raw.githubusercontent.com/saiteja-madha/docker-homelab/refs/heads/main/scripts/<script-name>.sh
```

Run the scripts manually instead of using one giant installer. This lets you verify each phase before continuing.

Recommended order:

```bash
00-base.sh        # base packages, sudo user, SSH key, updates
01-docker.sh      # Docker Engine and Compose plugin
02-tailscale.sh   # private network access
03-cockpit.sh     # server management UI
04-ufw.sh         # firewall rules
05-dokploy.sh     # deployment platform
06-cloudflared.sh # Cloudflare Tunnel
```

---

## Phase 0: Bootstrap Fresh VPS

Login as root:

```bash
ssh root@SERVER_IP
```

Run the base setup script (`00-base.sh`).

The script will ask for:

```text
VPS username
Server timezone
SSH public key
VPS password
```

Example:

```text
VPS username: sai
Server timezone: America/Los_Angeles
SSH public key: ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAA... your-key-comment
Enter password for sai: (hidden)
Confirm password: (hidden)
```

The SSH public key is optional but strongly recommended. Generate one on your laptop if needed:

```bash
ssh-keygen -t ed25519 -C "your_email@example.com"
```

Then copy the public key from:

```bash
~/.ssh/id_ed25519.pub
```

After reviewing the setup summary, confirm:

```text
Continue? [y/N]: y
```

This script handles system updates, base packages, timezone setup, unattended upgrades, sudo user creation, sudo group access, and optional SSH key installation.

The script is safe to rerun. Existing users and existing SSH keys are skipped.

After it finishes, test login from your laptop:

```bash
ssh VPS_USER@SERVER_IP
```

Example:

```bash
ssh sai@SERVER_IP
```

---

## Phase 1: Docker + Compose

Login as the sudo user:

```bash
ssh VPS_USER@SERVER_IP
```

Run the Docker setup script (`01-docker.sh`).

The script will ask for the VPS username to add to the Docker group:

```text
VPS username to add to docker group: sai
```

Confirm when prompted:

```text
Continue? [y/N]: y
```

This script removes conflicting Docker packages, adds Docker’s official apt repository and GPG key, installs Docker Engine, Buildx, and the Compose plugin, enables Docker, and adds the VPS user to the `docker` group.

After it finishes, log out and log back in so Docker group permissions apply:

```bash
exit
ssh VPS_USER@SERVER_IP
```

Verify:

```bash
docker version
docker compose version
docker run hello-world
```

If `docker run hello-world` works without `sudo`, Docker is ready.

---

## Phase 2: Tailscale

Run the Tailscale setup script (`02-tailscale.sh`).

The script will ask for:

```text
Tailscale auth key
Tailscale hostname
```

Both are optional.

If you leave the auth key empty, the script will print a login URL. Open it in your browser and approve the device.

Example interactive setup:

```text
Tailscale auth key:
Tailscale hostname: my-vps
```

Example auth-key setup:

```text
Tailscale auth key: tskey-auth-...
Tailscale hostname: my-vps
```

Confirm when prompted:

```text
Continue? [y/N]: y
```

This script installs Tailscale if needed, enables `tailscaled`, brings Tailscale up with SSH enabled, optionally sets a hostname, and avoids overwriting existing Tailscale settings unless you confirm.

If Tailscale is already authenticated, it may ask:

```text
Reconfigure Tailscale with this script's settings? [y/N]:
```

Usually choose `N` unless you intentionally want to reset and reapply the Tailscale settings.

Verify:

```bash
tailscale status
tailscale ip -4
```

Test Tailscale SSH from your laptop:

```bash
tailscale ssh VPS_USER@TAILSCALE_HOSTNAME
```

Or:

```bash
tailscale ssh VPS_USER@TAILSCALE_IP
```

Keep the Tailscale IP handy for later private access.

---

## Phase 3: Cockpit

Run the Cockpit setup script (`03-cockpit.sh`).

The script will ask for the Cockpit port:

```text
Cockpit port: 9090
```

Confirm when prompted:

```text
Continue? [y/N]: y
```

This script installs Cockpit, detects the Tailscale IPv4 address, binds Cockpit to the Tailscale IP when available, enables the Cockpit socket, and restarts it after configuration changes.

Recommended access:

```text
https://TAILSCALE_IP:9090
```

If Tailscale is not available, Cockpit uses its default configuration:

```text
https://SERVER_IP:9090
```

Cockpit login uses the VPS username and password. A password was already set during `00-base.sh`. To change it:

```bash
sudo passwd VPS_USER
```

Example:

```bash
sudo passwd sai
```

---

## Phase 4: UFW Firewall

Run this phase only after SSH access is confirmed.

Before continuing, make sure at least one of these works:

```bash
ssh VPS_USER@SERVER_IP
```

Preferably also confirm Tailscale SSH:

```bash
ssh VPS_USER@TAILSCALE_IP
```

Keep your VPS provider console available in case you lock yourself out.

Run the UFW setup script (`04-ufw.sh`).

The script will ask for the SSH port:

```text
SSH port: 22
```

Default behavior:

```text
ALLOW_PUBLIC_SSH=true
RESET_UFW=true
```

This resets existing UFW rules, allows public SSH temporarily, and allows inbound traffic through Tailscale if detected.

Confirm when prompted:

```text
Continue configuring UFW? [y/N]: y
```

This script installs UFW, optionally resets rules, denies incoming traffic by default, allows outgoing traffic, allows SSH, detects Tailscale, allows traffic on `tailscale0`, enables UFW, and prints the final firewall status.

After it finishes, confirm SSH over Tailscale from another terminal:

```bash
ssh -p SSH_PORT VPS_USER@TAILSCALE_IP
```

Example:

```bash
ssh -p 22 sai@100.x.y.z
```

Once Tailscale SSH works, tighten the firewall by removing the public SSH rule.

Check status:

```bash
sudo ufw status verbose
```

You can also remove public SSH manually:

```bash
sudo ufw status numbered
sudo ufw delete <rule-number>
```

Recommended final state:

* SSH through Tailscale
* Cockpit through Tailscale
* no unnecessary public admin ports
* public HTTP/HTTPS only if intentionally needed

---

## Phase 5: Dokploy

Run this phase after Docker is installed and working.

Verify Docker first:

```bash
docker version
docker compose version
```

Run the Dokploy setup script (`05-dokploy.sh`).

This script installs Dokploy, detects the `dokploy-network` Docker subnet, advertises that subnet through Tailscale when available, keeps Tailscale SSH enabled, recreates Dokploy Traefik with localhost-only HTTP/HTTPS bindings, and reconnects Traefik to the Dokploy network.

If the Dokploy subnet is detected, the script prints something like:

```text
Detected Dokploy subnet: 172.x.x.x/16
```

If Tailscale is available, approve the advertised route in the Tailscale Admin Console.

Dokploy should be available privately through Tailscale:

```text
http://TAILSCALE_IP:3000
```

Example:

```text
http://100.x.y.z:3000
```

Traefik HTTP and HTTPS are rebound to localhost only:

```text
http://127.0.0.1
https://127.0.0.1
```

Use this as the Cloudflare Tunnel target:

```text
http://127.0.0.1:80
```

Recommended security step:

```text
Block public inbound port 3000 in your VPS provider firewall.
```

Useful checks:

```bash
docker ps
docker network inspect dokploy-network | grep Subnet
```

---

## Phase 6: Cloudflared

Run this phase after Dokploy is installed.

Run the Cloudflared setup script (`06-cloudflared.sh`).

If no existing `cloudflared` service is found, the script asks for a Cloudflare Tunnel token.

Get it from:

```text
Cloudflare Zero Trust → Networks → Tunnels → Create Tunnel
```

Then paste the token when prompted:

```text
Cloudflared tunnel token: <your-cloudflare-tunnel-token>
```

If a `cloudflared` service already exists, the script asks:

```text
Reinstall cloudflared service with a new token? [y/N]:
```

Usually choose `N` if the existing tunnel works. Choose `Y` only if replacing the service token.

Confirm when prompted:

```text
Continue? [y/N]: y
```

This script checks for an existing service, optionally reinstalls it with a new token, detects `amd64` or `arm64`, downloads the latest `cloudflared` Debian package, installs or updates `cloudflared`, enables and restarts the service, and prints service status.

Verify:

```bash
systemctl status cloudflared --no-pager
cloudflared --version
```

Next, configure Public Hostnames in Cloudflare Zero Trust.

For services behind Dokploy, point the Cloudflare Tunnel hostname to:

```text
http://127.0.0.1:80
```

You do not need to open public ports `80`, `443`, or `8088` in UFW for Cloudflare Tunnel traffic.
