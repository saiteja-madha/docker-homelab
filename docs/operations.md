# Operations

## Routine health checks

```bash
tailscale status
sudo ufw status verbose
sudo iptables -S DOCKER-USER
sudo ss -lntup
docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'
systemctl --no-pager --failed
systemctl is-active cloudflared cockpit.socket docker tailscaled
```

Expected properties:

- Every Docker-published port (including `TAILSCALE_IP:3000`) is reachable through Tailscale and unreachable from the public IP.
- Cockpit listens on the Tailscale address.
- Traefik listens on loopback ports `80` and `443`.
- The webhook proxy listens on loopback port `8088`.
- Public applications and a GitHub test delivery succeed through Cloudflare.

## Updating the host

Use a maintenance window and confirm recent backups first:

```bash
sudo apt-get update
apt list --upgradable
sudo apt-get upgrade
sudo systemctl --failed
```

Reboot when required, then repeat the health checks. Do not automatically prune
Docker volumes; they may contain application data.

## Updating Dokploy

Before upgrading:

1. Record the current Dokploy and Traefik image versions.
2. Create and verify a control-plane backup.
3. Confirm recent application database and named-volume backups.
4. Read the target release notes and note migrations or breaking changes.

Use Dokploy's supported update path. The provisioning script reapplies this
repository's loopback Traefik binding and dashboard firewall rule, so rerun it
only when that full behavior is intended:

```bash
sudo DOKPLOY_VERSION=vX.Y.Z bash scripts/05-dokploy.sh
```

Afterward, inspect Traefik's image and bindings, validate applications, test the
webhook, and create a fresh backup.

## Updating the webhook proxy

The proxy is a Dokploy-managed Compose service connected to this GitHub
repository. Review changes to `tools/dokploy-webhook-proxy`, then deploy through
Dokploy or allow the configured GitHub webhook to trigger deployment. Use the
Dokploy UI for status and logs.

After an image or nginx configuration update, verify the loopback listener, the
Cloudflare hostname, one valid GitHub test delivery, and rejection of an unsigned
request.

## Configuration drift

Dokploy application definitions belong in Dokploy and its backups. Avoid adding
them here as a second deployment source. Changes to host policy or provisioning
belong in this repository and should be reviewed before application to a server.

After manual emergency changes, either encode the durable host change here or
explicitly document that it is temporary. Record:

- repository commit;
- Ubuntu version;
- Dokploy and Traefik image versions;
- Dokploy network subnet;
- Tailscale hostname and advertised routes;
- Cloudflare tunnel and hostname mapping identifiers;
- last restore-test result.

Do not record secrets in the repository.

## Decommissioning

Before deleting a server, take final backups and perform the required integrity
checks. Then revoke the Tailscale machine, Cloudflare tunnel token, GitHub webhook
secret, Dokploy/API tokens, server SSH keys, and any server-scoped S3 credentials.
Remove stale DNS and provider-firewall rules.
