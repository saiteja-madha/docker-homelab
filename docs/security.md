# Security Notes

## Principles

- Use a non-root sudo user.
- Use SSH keys instead of passwords.
- Keep admin tools behind Tailscale.
- Use UFW as the server firewall.
- Keep real secrets out of GitHub.
- Store runtime secrets in Dokploy.
- Store backup secrets in Bitwarden.

## Do Not Commit

- Real `.env` files
- Private keys
- API keys
- Passwords
- Recovery codes

## Before Tightening SSH

Confirm all of these work first:

```bash
ssh sai@SERVER_IP
sudo whoami
tailscale status
```

Then confirm you have emergency console access through the VPS provider panel.
