# Networking

## Public Services

These may be exposed publicly:

| Service | Public |
|---|---:|
| Websites | Yes |
| APIs | Yes |

## Private Services

These should only be accessible through Tailscale:

| Service | Public | Tailscale |
|---|---:|---:|
| SSH | Prefer no | Yes |
| Cockpit | No | Yes |
| Dokploy | No | Yes |
| PostgreSQL | No | Yes |
| Redis | No | Yes |

## Rule

Only public apps should be exposed to the internet.

Admin tools should stay private.

## Suggested Ports

| Port | Service | Exposure |
|---:|---|---|
| 22 | SSH | Temporary public, later Tailscale preferred |
| 80 | HTTP | Public |
| 443 | HTTPS | Public |
| 9090 | Cockpit | Tailscale only |
| 3000/other | Dokploy dashboard/app internals | Tailscale only unless intentionally exposed |
