# Dokploy webhook proxy

This Dokploy-managed Compose service permits GitHub-driven deployments while the
Dokploy dashboard remains private on Tailscale.

```text
GitHub webhook
  → HTTPS webhook-only hostname at Cloudflare
  → Cloudflare Tunnel
  → 127.0.0.1:8088
  → POST /api/deploy/github only
  → 127.0.0.1:3000/api/deploy/github
```

## Deploy with Dokploy

1. Access Dokploy through Tailscale.
2. Create a Compose service connected to this GitHub repository.
3. Select `tools/dokploy-webhook-proxy/docker-compose.yml` as the Compose file.
4. Deploy it manually the first time.
5. Configure a dedicated Cloudflare Tunnel public hostname:

   ```text
   deploy.example.com → http://127.0.0.1:8088
   ```

6. Configure the GitHub webhook URL:

   ```text
   https://deploy.example.com/api/deploy/github
   ```

After the initial deployment, repository updates can use the configured GitHub
webhook. During disaster recovery, restore Dokploy, access it through Tailscale,
and manually deploy this service once before testing webhook automation.

Do not open `8088` in UFW or the provider firewall. Direct public exposure is not
a supported normal configuration.

## Security properties

- nginx listens only on host loopback;
- only the exact deploy path is routed;
- only POST is accepted at that path;
- all Linux capabilities are dropped;
- privilege escalation and a writable container filesystem are disabled;
- GitHub signature and delivery headers pass through unchanged;
- the Dokploy dashboard and all other API paths remain unreachable through this
  proxy.

The proxy does **not** validate the GitHub signature itself. Dokploy must validate
the configured webhook secret. After installation and every Dokploy upgrade,
send one valid GitHub test delivery and verify an unsigned POST is rejected.

A Cloudflare WAF rule may additionally restrict the hostname/path to GitHub's
current webhook source ranges. Do not use an interactive Cloudflare Access login
policy; GitHub cannot complete it. IP restrictions supplement rather than replace
signature verification.

## Verification

From the VPS:

```bash
curl -i http://127.0.0.1:8088/
curl -i -X GET http://127.0.0.1:8088/api/deploy/github
curl -i -X POST http://127.0.0.1:8088/api/deploy/github
```

The root path must return `404`; GET on the deploy path must be denied; and an
unsigned POST must be rejected by Dokploy. A valid GitHub delivery should return
the status expected by Dokploy within GitHub's delivery timeout. Use the Dokploy
UI for container status, deployment history, and logs.
