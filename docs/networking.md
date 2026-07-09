# Networking

This Dokploy instance uses two access paths:

1. **Public application traffic** goes through Cloudflare Tunnel.
2. **Private and admin traffic** goes through Tailscale.

The VPS should not expose Dokploy Traefik or the Dokploy dashboard directly to the public internet.

---

## Architecture

### Public Applications

```text
Internet
  -> Cloudflare
  -> Cloudflare Tunnel
  -> 127.0.0.1:80 on VPS
  -> Dokploy Traefik
  -> Application container on dokploy-network
```

### Private Services

```text
Tailscale client
  -> VPS Tailscale IP
  -> Docker published port bound to Tailscale IP
  -> Private container
```

### Dokploy Dashboard

```text
Tailscale client
  -> VPS Tailscale IP:3000
  -> Dokploy dashboard
```

---

## Cloudflare Tunnel

Cloudflare Tunnel routes public traffic to Traefik on the host loopback interface.

Use this tunnel configuration:

```yaml
ingress:
  - hostname: domain.com
    service: http://127.0.0.1:80

  - hostname: "*.domain.com"
    service: http://127.0.0.1:80

  - service: http_status:404
```

Do **not** override the `Host` header unless intentionally routing all requests as a single hostname.

Traefik needs to receive the original hostname:

```http
Host: app.domain.com
```

This allows Dokploy-generated Traefik labels to match the correct service.

---

## DNS

Cloudflare DNS should route both the root domain and wildcard subdomains through the tunnel.

```text
domain.com     -> Cloudflare Tunnel
*.domain.com   -> Cloudflare Tunnel
```

Example application domains:

```text
app.domain.com
api.domain.com
admin.domain.com
```

---

## Traefik Binding

Dokploy Traefik is recreated with localhost-only bindings.

This prevents public access to Traefik through the VPS public IP.

```bash
docker stop dokploy-traefik 2>/dev/null || true
docker rm dokploy-traefik 2>/dev/null || true

docker run -d \
  --name dokploy-traefik \
  --restart always \
  -v /etc/dokploy/traefik/traefik.yml:/etc/traefik/traefik.yml \
  -v /etc/dokploy/traefik/dynamic:/etc/dokploy/traefik/dynamic \
  -v /var/run/docker.sock:/var/run/docker.sock:ro \
  -p 127.0.0.1:80:80/tcp \
  -p 127.0.0.1:443:443/tcp \
  -p 127.0.0.1:443:443/udp \
  traefik:v3.6.7

docker network connect dokploy-network dokploy-traefik 2>/dev/null || true
```

Expected bindings:

```text
127.0.0.1:80
127.0.0.1:443
```

Avoid public bindings:

```text
0.0.0.0:80
0.0.0.0:443
```

---

## Dokploy Network

Dokploy uses the Docker network:

```text
dokploy-network
```

When a domain is configured for a Dokploy service, Dokploy adds the required Traefik labels and connects the service to the Dokploy network.

Public app routing works because Traefik and the target service are on the same Docker network.

```text
Cloudflare Tunnel
  -> host loopback Traefik
  -> dokploy-network
  -> app container
```

---

## Private Services with Tailscale

Private containers should publish ports only on the VPS Tailscale IP.

Use this pattern in Docker Compose:

```yaml
services:
  app:
    image: example/app
    ports:
      - "${TAILSCALE_IP}:8080:8080"
```

Example with a real Tailscale IP:

```yaml
services:
  app:
    image: example/app
    ports:
      - "100.x.y.z:8080:8080"
```

This makes the service reachable at:

```text
http://100.x.y.z:8080
```

The service will not be exposed on the public VPS interface.

Avoid this for private services:

```yaml
ports:
  - "8080:8080"
```

That publishes the port on all host interfaces, usually including the public IP.

---

## Dokploy Dashboard Access

The Dokploy dashboard runs on port `3000`.

It should be restricted to Tailscale only.

Recommended access:

```text
http://TAILSCALE_IP:3000
```

Do not expose the Dokploy dashboard publicly.

Block public inbound access to port `3000` using the VPS provider firewall.

If possible, bind the Dokploy dashboard only to localhost or the Tailscale IP.

---

## Tailscale Subnet Route

The Dokploy Docker network subnet can be advertised through Tailscale.

Detect the subnet:

```bash
docker network inspect dokploy-network -f '{{range .IPAM.Config}}{{.Subnet}}{{end}}'
```

Advertise it:

```bash
sudo tailscale set --ssh --advertise-routes="<DOKPLOY_SUBNET>"
```

Then approve the route in the Tailscale Admin Console.

This allows devices on the tailnet to reach services inside the Dokploy Docker network when routing rules allow it.

---

## Verification

Check listening ports:

```bash
ss -tulpn | grep -E ':80|:443|:3000'
```

Traefik should be bound to localhost:

```text
127.0.0.1:80
127.0.0.1:443
```

Check that Traefik is not public:

```bash
curl -I http://PUBLIC_SERVER_IP
```

This should not expose the Traefik entrypoint directly.

Check that Dokploy is not public:

```bash
curl -I http://PUBLIC_SERVER_IP:3000
```

This should fail, timeout, or be blocked.

Check Dokploy over Tailscale:

```bash
curl -I http://TAILSCALE_IP:3000
```

Check an application through Cloudflare:

```bash
curl -I https://app.domain.com
```

---

## Security Rules

### Public Applications

Use Dokploy domains.

Do not manually publish public ports unless necessary.

Expected path:

```text
Cloudflare Tunnel -> Traefik -> app container
```

### Private Applications

Bind ports to the Tailscale IP.

```yaml
ports:
  - "${TAILSCALE_IP}:8080:8080"
```

### Admin Services

Do not expose admin dashboards publicly.

Use Tailscale-only access.

### Avoid

Avoid publishing private services like this:

```yaml
ports:
  - "8080:8080"
```

Avoid exposing these publicly:

```text
:3000  Dokploy dashboard
:80    Traefik direct HTTP
:443   Traefik direct HTTPS
```

---

## Expected Final State

```text
Cloudflare Tunnel:
  domain.com     -> http://127.0.0.1:80
  *.domain.com   -> http://127.0.0.1:80

Traefik:
  127.0.0.1:80
  127.0.0.1:443

Dokploy dashboard:
  Tailscale-only
  public :3000 blocked

Public apps:
  routed by Cloudflare Tunnel and Traefik

Private apps:
  ports bound to Tailscale IP only
```
