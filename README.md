# VPS Provisioning Toolkit

Rebuildable host provisioning and disaster-recovery documentation for a private
Dokploy server on Ubuntu 24.04 LTS.

This repository intentionally does **not** contain application stacks,
application configuration, environment variables, or a deployment workflow.
Dokploy owns that state and GitHub provides application source code. This repo
owns the host provisioning and the source configuration for the small webhook
bridge required by a private Dokploy control plane; Dokploy deploys that bridge.

## Responsibility boundary

| Owner | Responsibilities |
|---|---|
| This repository | OS bootstrap, Docker, Tailscale, Cockpit, firewall, Dokploy installation, Cloudflare Tunnel, webhook proxy source, recovery runbooks |
| Dokploy | Projects, applications, application Compose definitions, webhook proxy deployment, domains, environment/configuration, deployments, backup schedules |
| GitHub application repositories | Application source and any application-owned deployment files |
| S3-compatible storage | Dokploy control-plane, database, and named-volume backups |
| Password manager/off-server records | S3 credentials, Cloudflare access, Tailscale access, GitHub recovery, DNS registrar access |

## Provisioning order

Clone and review the repository, then run each phase separately:

```bash
sudo bash scripts/00-base.sh
sudo bash scripts/01-docker.sh
sudo bash scripts/02-tailscale.sh
sudo bash scripts/03-cockpit.sh
sudo bash scripts/04-ufw.sh
sudo bash scripts/05-dokploy.sh
sudo bash scripts/06-cloudflared.sh
```

`scripts/07-dev-tools.sh` is optional and must be run as the non-root user.

Do not combine the phases into an unattended one-line installer. Verify access
after each security-sensitive step and keep the VPS provider console available.

## Documentation

- [Architecture](docs/architecture.md)
- [Provisioning](docs/provisioning.md)
- [Networking](docs/networking.md)
- [Backup and recovery](docs/backup-and-recovery.md)
- [Security](docs/security.md)
- [Operations](docs/operations.md)

Start with the [provisioning guide](docs/provisioning.md) for a new server or the
[recovery runbook](docs/backup-and-recovery.md) after a failure.
