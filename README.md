# VPS Infra

Personal VPS infrastructure setup for a lean homelab-style VPS.

## Core Stack

| Category | Choice |
|---|---|
| OS | Ubuntu 24.04 LTS |
| Containers | Docker + Compose |
| Deployment | Dokploy |
| Server Management | Cockpit |
| Private Access | Tailscale |
| Firewall | UFW |
| Updates | unattended-upgrades |
| Version Control | GitHub |

## Access Model

Public internet should only expose public apps.

Admin services should be private through Tailscale:

- SSH
- Cockpit
- Dokploy
- PostgreSQL
- Redis

## Setup Order

Run scripts one by one and verify after each phase:

```bash
sudo bash scripts/00-base.sh
sudo bash scripts/01-docker.sh
sudo bash scripts/02-tailscale.sh
sudo bash scripts/03-cockpit.sh
sudo bash scripts/04-ufw.sh
sudo bash scripts/05-dokploy.sh
```

Do not run everything as one giant installer until you are comfortable recovering the VPS.

## Fresh VPS Quick Start

Login as root:

```bash
ssh root@SERVER_IP
```

Install minimal bootstrap tools:

```bash
apt update && apt install -y git curl ca-certificates unzip
```

Clone or copy this repo, then:

```bash
cd vps-infra
cp .env.example .env
nano .env
bash scripts/00-base.sh
```

After `00-base.sh`, test login as your sudo user from your laptop:

```bash
ssh sai@SERVER_IP
```

Then continue from the copied repo in the user's home:

```bash
cd ~/vps-infra
sudo bash scripts/01-docker.sh
```
