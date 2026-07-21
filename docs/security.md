# Security

## Security model

Public users reach applications only through Cloudflare Tunnel. Administrators
reach SSH, Cockpit, and Dokploy through Tailscale. The GitHub webhook bridge is
the sole narrow public path into the Dokploy control plane.

Use the VPS provider firewall, UFW, Docker's `DOCKER-USER` chain, loopback
bindings, Tailscale policy, and application authentication as independent
layers.

## Current controls and residual risks

| Area                     | Current control                                                                                                       | Residual risk / required practice                                                                                  |
| ------------------------ | --------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------ |
| Administrative access    | SSH, Cockpit, and Dokploy use Tailscale; Cockpit fails closed without a Tailscale address                             | Review Tailscale users, devices, and ACLs/grants; retain provider-console recovery                                 |
| Host firewall            | UFW handles host ingress; `DOCKER-USER` restricts all Docker-published ports to Tailscale only; the provider firewall adds an outer layer | Docker networking and interface changes can invalidate assumptions; verify externally after upgrades and reboots   |
| Docker privilege         | Docker group access is limited to the intended administrator                                                          | Docker group membership and Docker socket access are root-equivalent trust boundaries                              |
| Dokploy Traefik          | HTTP/HTTPS bind to loopback and the installed Dokploy-selected image is preserved                                     | Dokploy or Traefik upgrades may change runtime assumptions; recheck image, mounts, network, and bindings           |
| Remote installers        | Installers are downloaded before execution and Dokploy supports an explicit version                                   | Upstream privileged code remains a supply-chain boundary; review releases and pin versions for controlled recovery |
| Cloudflare Tunnel        | Token prompts are hidden and tokens are unset after service installation                                              | The downloaded latest package is not checksum-pinned; protect and rotate tunnel credentials                        |
| Webhook bridge           | Dokploy deploys an unprivileged, read-only, capability-free proxy that listens on loopback and forwards one POST path | Host networking remains powerful, and Dokploy must validate GitHub signatures; test valid and unsigned deliveries  |
| Backups                  | Control-plane, database, and named-volume backups are separated and stored off-server                                 | Bind mounts need separate coverage; credentials and restore procedures must remain available outside the VPS       |
| Optional developer tools | Go archives are SHA-256 verified; NVM is version-pinned and runs as a non-root user                                   | The NVM installer is still upstream code; omit optional tools from hosts that do not need them                     |

Prefer a reviewed repository commit, explicit upstream versions, protected
accounts, and a maintenance window for privileged changes.

## SSH hardening

Only after SSH-key and provider-console access are confirmed, create a reviewed
drop-in under `/etc/ssh/sshd_config.d/` that disables root login and password
authentication. Validate before reload:

```bash
sudo sshd -t
sudo systemctl reload ssh
```

Keep an existing session open while testing a new one. Tailscale SSH policy must
also restrict which identities may connect; installing Tailscale alone does not
create an adequate authorization policy.

## Secrets

- Never commit `.env` files, private keys, tunnel tokens, S3 keys, API keys, or
  webhook secrets.
- Use separate, least-privilege S3 credentials for backup storage.
- Keep recovery credentials in an off-server password manager.
- Prefer short-lived or one-time Tailscale auth keys.
- Enable MFA for Dokploy, GitHub, Cloudflare, Tailscale, the VPS provider, S3,
  and the DNS registrar.
- Rotate all relevant credentials after a suspected host compromise.

Environment variables passed to root scripts may be observable to privileged
local processes. Interactive hidden prompts are preferable for tokens.

## Webhook security

The proxy narrows exposure but does not itself authenticate GitHub. GitHub's
`X-Hub-Signature-256` and delivery headers are passed unchanged to Dokploy, which
must validate the configured secret. Verify this after every install or upgrade
by testing one valid GitHub delivery and one unsigned request.

Use HTTPS at Cloudflare, a dedicated hostname, an exact path, POST-only proxying,
and optional WAF source-range restrictions. GitHub source IP ranges change, so
automate or periodically review any allowlist. Signature validation remains the
primary integrity control.

References:

- <https://docs.github.com/en/webhooks/using-webhooks/validating-webhook-deliveries>
- <https://docs.github.com/en/webhooks/using-webhooks/best-practices-for-using-webhooks>

## Patch and access review

At least monthly:

- review Ubuntu and container security updates;
- review Tailscale users, devices, ACLs/grants, and advertised routes;
- review Dokploy administrators, API keys, Git providers, and deployment logs;
- review Cloudflare tunnels, DNS records, WAF rules, and account sessions;
- review listening sockets and Docker published ports;
- confirm backup jobs and alerts are succeeding.
