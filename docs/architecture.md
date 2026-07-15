# Architecture

## Ownership model

```mermaid
flowchart LR
    Repo["Provisioning repository"] -->|"builds and secures"| Host["Ubuntu VPS"]
    Host --> Dokploy["Private Dokploy control plane"]
    Repo -->|"webhook proxy source"| Dokploy
    GitHub["GitHub application repositories"] -->|"source and webhooks"| Dokploy
    Dokploy -->|"deploys"| Apps["Applications and databases"]
    Dokploy -->|"scheduled backups"| S3["S3-compatible storage"]
    Vault["Off-server password manager"] -->|"recovery credentials"| Host
    Vault -->|"S3, Cloudflare, GitHub, Tailscale"| S3
```

The repository owns host provisioning and the proxy's source configuration.
Dokploy owns application and Compose deployment state, including deployment of
the proxy, plus configuration, domains, and backup schedules. Keeping a second
deployment mechanism here would create two control planes with ambiguous
precedence.

## Network design

```mermaid
flowchart TB
    Internet["Public users"] --> CF["Cloudflare edge"]
    GitHub["GitHub webhooks"] --> CF
    CF --> Tunnel["cloudflared on VPS"]
    Tunnel -->|"applications: 127.0.0.1:80"| Traefik["Dokploy Traefik"]
    Tunnel -->|"webhook host: 127.0.0.1:8088"| Proxy["Restricted webhook proxy"]
    Proxy -->|"POST /api/deploy/github"| Panel["Dokploy :3000"]
    Traefik --> Apps["Dokploy-managed services"]
    Admin["Administrator device"] --> Tailnet["Tailscale"]
    Tailnet --> Panel
    Tailnet --> Cockpit["Cockpit"]
    Tailnet --> SSH["SSH"]
```

Traefik and the proxy bind only to loopback. Administrative services are
reachable through Tailscale. The VPS provider firewall and host firewall form
additional layers rather than the primary public application path.

## Recovery design

```mermaid
flowchart LR
    Failure["Lost or replaced VPS"] --> Provision["Provision host from repository"]
    Provision --> Install["Install matching Dokploy version"]
    Secrets["Off-server recovery credentials"] --> Install
    Install --> Control["Restore Dokploy database and /etc/dokploy"]
    S3["S3 backups"] --> Control
    Control --> Data["Restore application databases and named volumes"]
    S3 --> Data
    Data --> Integrations["Repair DNS, tunnel, GitHub, and Tailscale settings"]
    Integrations --> Validate["Validate externally and record restore test"]
```

The S3 destination cannot be the only place where its own credentials are
stored. Credentials, account recovery methods, the last known Dokploy version,
and the repository commit must remain available off-server.
