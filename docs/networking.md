# Networking

The server has two deliberate ingress paths: Cloudflare Tunnel for public
application traffic and Tailscale for administration. There should be no direct
public path to Dokploy, Cockpit, SSH, Traefik, or the webhook proxy.

## Traffic policy

| Traffic            | Path                                                              | Public host port          |
| ------------------ | ----------------------------------------------------------------- | ------------------------- |
| Applications       | Internet → Cloudflare → tunnel → `127.0.0.1:80` → Traefik         | None                      |
| GitHub deployments | GitHub → Cloudflare → tunnel → `127.0.0.1:8088` → proxy → Dokploy | None                      |
| Any Docker port    | Tailscale → VPS any port                                          | Blocked                   |
| Cockpit            | Tailscale → bound Tailscale address, normally `9090`              | None                      |
| SSH                | Tailscale SSH or SSH through `tailscale0`                         | Disabled after validation |

## Cloudflare hostnames

Configure public application hostnames with an origin of:

```text
http://127.0.0.1:80
```

Use a dedicated hostname for GitHub deliveries:

```text
deploy.example.com → http://127.0.0.1:8088
```

Do not put the interactive Dokploy dashboard behind that webhook hostname.
Cloudflare Access login policies are unsuitable for GitHub webhook delivery
unless a non-interactive authentication design is explicitly supported. Prefer
the exact proxy path plus GitHub signature validation, and optionally a
Cloudflare WAF rule using GitHub's current webhook source ranges.

## Docker and firewall behavior

Docker-published ports can bypass ordinary UFW expectations. The `DOCKER-USER`
chain therefore accepts all inbound traffic from `tailscale0` and drops all
inbound traffic from the public interface. This keeps every Docker-published
port — including the Dokploy dashboard and any future database — accessible only
through Tailscale. Keep the provider firewall as an independent outer layer.

Inspect the effective rules:

```bash
sudo iptables -S DOCKER-USER
sudo ufw status verbose
sudo ss -lntup
docker ps --format 'table {{.Names}}\t{{.Ports}}'
```

Expected Traefik bindings after provisioning:

```text
127.0.0.1:80
127.0.0.1:443/tcp
127.0.0.1:443/udp
```

The webhook proxy must listen only on `127.0.0.1:8088`.

## Tailscale subnet routes

Dashboard and Cockpit access do not require advertising the Docker subnet.
Advertise `dokploy-network` only if a client genuinely needs direct container IP
access. Subnet routing expands the reachable network and requires approval in
the Tailscale admin console.

Detect the current subnet:

```bash
docker network inspect dokploy-network \
  --format '{{range .IPAM.Config}}{{.Subnet}}{{end}}'
```

When enabled through `ADVERTISE_DOKPLOY_SUBNET=true`, verify Tailscale ACLs/grants
restrict which users and devices may reach it.

## Private application services

Prefer Tailscale-aware application access, a Tailscale sidecar, or a published
port explicitly bound to the host's Tailscale address. Avoid an unqualified
mapping such as `8080:8080`, which normally binds all interfaces.

```yaml
ports:
  - "${TAILSCALE_IP}:8080:8080"
```

Dokploy owns such application Compose definitions; this repository documents
the policy but does not store them.

## Verification from outside

Run these tests from a device that is **not** connected to Tailscale:

```bash
curl --connect-timeout 5 http://PUBLIC_IP:3000
curl --connect-timeout 5 http://PUBLIC_IP:8088
# Add any Docker-published port to confirm it is also blocked
```

All must fail. Then verify the public app hostname works and the webhook
hostname returns a failure for `/` and for methods other than the configured
GitHub POST delivery.
