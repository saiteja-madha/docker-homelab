# Recovery Guide

## Emergency Access

If SSH or Tailscale breaks, use the VPS provider console.

## Important Backups

Store these in Bitwarden:

- VPS provider login
- Root password
- Sudo user password
- Tailscale recovery info
- Dokploy admin credentials
- Cloudflare credentials
- App secrets
- Database passwords

## Rebuild Process

1. Reinstall Ubuntu.
2. Clone or upload this repository.
3. Create `.env` from `.env.example`.
4. Run setup scripts in order.
5. Reconnect Tailscale.
6. Restore Dokploy/apps.
7. Restore databases if needed.
