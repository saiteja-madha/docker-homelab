# VPS Install Guide

This guide assumes a fresh Ubuntu VPS.

## Recommended Approach

Use the repo and scripts, but run scripts manually one by one:

```bash
00-base.sh       # base packages, sudo user, SSH key, updates
01-docker.sh     # Docker Engine and Compose plugin
02-tailscale.sh  # private network access
03-cockpit.sh    # server management UI
04-ufw.sh        # firewall rules
05-dokploy.sh    # deployment platform
```

This is safer than one giant installer because you can verify each phase before moving on.

## Phase 0: Bootstrap Fresh VPS

Login as root:

```bash
ssh root@SERVER_IP
```

Install minimal tools:

```bash
apt update
apt install -y git curl ca-certificates unzip
```

Clone this repository:

```bash
git clone https://github.com/saiteja-madha/docker-homelab.git
cd docker-homelab
```

Or upload/extract the repo zip and enter the folder:

```bash
unzip docker-homelab.zip
cd docker-homelab
```

Create the local environment file:

```bash
cp .env.example .env
nano .env
```

Example:

```env
VPS_USER=sai
SSH_PUBLIC_KEY=ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAA... your-key-comment
SERVER_TIMEZONE=America/Los_Angeles
REPO_NAME=docker-homelab
```

Run base setup:

```bash
bash scripts/00-base.sh
```

After the script finishes, test login from your laptop:

```bash
ssh sai@SERVER_IP
```

## Phase 1: Base Server

The base script handles:

- System updates
- Base package installation
- Timezone setup
- unattended-upgrades
- sudo user creation
- optional SSH key installation
- copying this repo to the new user's home directory

Run:

```bash
bash scripts/00-base.sh
```

## Phase 2: Docker + Compose

Login as the sudo user:

```bash
ssh sai@SERVER_IP
```

Go to the repo:

```bash
cd ~/docker-homelab
```

Run Docker setup:

```bash
sudo bash scripts/01-docker.sh
```

Log out and log back in so Docker group permissions apply:

```bash
exit
ssh sai@SERVER_IP
```

Verify:

```bash
docker version
docker compose version
docker run hello-world
```

## Phase 3: Tailscale

Run:

```bash
cd ~/docker-homelab
sudo bash scripts/02-tailscale.sh
```

If `TAILSCALE_AUTH_KEY` is empty, the script will print a login URL.

Verify:

```bash
tailscale status
tailscale ip -4
```

## Phase 4: Cockpit

Run:

```bash
cd ~/docker-homelab
sudo bash scripts/03-cockpit.sh
```

Cockpit listens on port `9090` by default.

Recommended access:

```text
https://TAILSCALE_IP:9090
```

## Phase 5: UFW Firewall

Run this only after public SSH and Tailscale access are working:

```bash
cd ~/docker-homelab
sudo bash scripts/04-ufw.sh
```

The default firewall policy allows:

- SSH on port 22
- HTTP on port 80
- HTTPS on port 443
- Cockpit only through Tailscale interface

Later, after confirming Tailscale SSH/admin access, you can tighten SSH further.

## Phase 6: Dokploy

Run:

```bash
cd ~/docker-homelab
sudo bash scripts/05-dokploy.sh
```

After install, keep Dokploy private through Tailscale/firewall unless you intentionally expose it.
